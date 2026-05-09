//
//  BrowserModel+NavigationDelegate.swift
//  macos-app
//

import AppKit
import Foundation
import WebKit

extension BrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard let tab = tab(for: webView) else { return }
        if activeTabID == tab.id {
            BrowserDebugLogging.startTimingSession(
                pageURL: webView.url?.absoluteString,
                pageHost: webView.url?.host,
                reason: "navigation-start"
            )
        }
        logNavigationEvent("didStartProvisionalNavigation", webView: webView, tab: tab)

        tab.errorMessage = nil
        tab.hasAttemptedNavigation = true
        tab.loadingURL = webView.url ?? tab.loadingURL

        if activeTabID == tab.id {
            errorMessage = nil
            hasAttemptedNavigation = true
            isLoading = true
            estimatedProgress = max(0.08, webView.estimatedProgress)
            resetScreenshotForNavigation()
            resetXHRTracking(for: webView.url)
        }

        BrowserWebExtension.shared.didChangeTab(tab, properties: [.loading, .URL])
        syncPageState(from: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let tab = tab(for: webView) else { return }
        logNavigationEvent("didCommit", webView: webView, tab: tab)

        tab.errorMessage = nil
        tab.navigationFallbacks = []
        tab.loadingURL = webView.url ?? tab.loadingURL

        if activeTabID == tab.id {
            errorMessage = nil
            navigationFallbacks = []
        }

        BrowserWebExtension.shared.didChangeTab(tab, properties: [.loading, .URL])
        syncPageState(from: webView)

        if let url = webView.url {
            recordVisitedURL(url, identityID: tab.identityID)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let tab = tab(for: webView) else { return }
        logNavigationEvent("didFinish", webView: webView, tab: tab)

        tab.errorMessage = nil
        tab.loadingURL = nil

        if activeTabID == tab.id {
            errorMessage = nil
            estimatedProgress = 1
        }

        BrowserWebExtension.shared.didChangeTab(tab, properties: [.loading, .title, .URL])
        syncPageState(from: webView)

        if activeTabID == tab.id {
            markScreenshotDirty(scheduleAfter: 0.25)
            botTerminal.refreshIfOpen(
                currentURL: webView.url,
                pageTitle: webView.title,
                viewportMode: viewportMode,
                xhrCount: xhrRecords.count
            )
        }

        if let url = webView.url {
            recordVisitedURL(url, identityID: tab.identityID)
        }

        if activeTabID == tab.id {
            fillSavedLoginForCurrentSite(reportsMissingLogin: false)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logNavigationFailure("didFail", webView: webView, error: error)
        handleNavigationError(error, in: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logNavigationFailure("didFailProvisionalNavigation", webView: webView, error: error)
        if loadNextFallback(after: error, in: webView) {
            return
        }

        handleNavigationError(error, in: webView)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if let scheme = url.scheme?.lowercased(), !["http", "https", "about"].contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        guard navigationAction.targetFrame?.isMainFrame != false else {
            decisionHandler(.allow)
            return
        }

        BrowserDebugLogging.log(
            "[wkdomains-debug] navigation policy prepare url=\(url.absoluteString) type=\(navigationAction.navigationType.rawValue)"
        )
        guard let tab = tab(for: webView) else {
            decisionHandler(.allow)
            return
        }

        BrowserWebExtension.shared.prepareForNavigation(to: url, in: tab) {
            BrowserDebugLogging.log(
                "[wkdomains-debug] navigation policy allow url=\(url.absoluteString) type=\(navigationAction.navigationType.rawValue)"
            )
            decisionHandler(.allow)
        }
    }

    private func logNavigationEvent(_ event: String, webView: WKWebView, tab: BrowserTabState) {
        BrowserDebugLogging.log(
            "[wkdomains-debug] navigation \(event) tab=\(String(tab.id.uuidString.prefix(8))) url=\(webView.url?.absoluteString ?? "nil") loading=\(webView.isLoading) progress=\(String(format: "%.3f", webView.estimatedProgress)) title=\(webView.title ?? "nil")"
        )
    }

    private func logNavigationFailure(_ event: String, webView: WKWebView, error: Error) {
        let nsError = error as NSError
        BrowserDebugLogging.log(
            "[wkdomains-debug] navigation \(event) url=\(webView.url?.absoluteString ?? "nil") domain=\(nsError.domain) code=\(nsError.code) message=\(error.localizedDescription)"
        )
    }

    private func handleNavigationError(_ error: Error, in webView: WKWebView) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }

        guard let tab = tab(for: webView) else { return }
        tab.navigationFallbacks = []
        tab.errorMessage = error.localizedDescription
        tab.loadingURL = nil

        if activeTabID == tab.id {
            navigationFallbacks = []
            isLoading = false
            estimatedProgress = 0
            errorMessage = error.localizedDescription
            finishScreenshotWaiters(with: .failure(error))
        }

        BrowserWebExtension.shared.didChangeTab(tab, properties: [.loading, .URL])
        refreshPublishedTabs()
    }

    private func loadNextFallback(after error: Error, in webView: WKWebView) -> Bool {
        let nsError = error as NSError
        guard let tab = tab(for: webView) else { return false }
        guard nsError.code != NSURLErrorCancelled,
              !tab.navigationFallbacks.isEmpty
        else {
            return false
        }

        let nextURL = tab.navigationFallbacks.removeFirst()
        tab.errorMessage = nil
        tab.displayAddressText = nextURL.absoluteString
        tab.loadingURL = nextURL

        if activeTabID == tab.id {
            navigationFallbacks = tab.navigationFallbacks
            errorMessage = nil
            displayAddressText = nextURL.absoluteString
            isSecurePage = nextURL.scheme?.lowercased() == "https"
            resetXHRTracking(for: nextURL)
        }

        BrowserWebExtension.shared.didChangeTab(tab, properties: [.loading, .URL])
        webView.load(URLRequest(url: nextURL))
        return true
    }
}
