//
//  BrowserModel+WebKitDelegates.swift
//  macos-app
//

import AppKit
import Foundation
import WebKit

extension BrowserModel: BrowserContextMenuDelegate {}

extension BrowserModel: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else {
            return
        }

        switch message.name {
        case "wkdomainsXHR":
            recordXHRMessage(body)
        case "wkdomainsRender":
            markScreenshotDirty(scheduleAfter: 0.35)
        case "wkdomainsConsole":
            recordConsoleMessage(body)
        case "wkdomainsLogin":
            saveCapturedLogin(body)
        default:
            return
        }
    }
}

extension BrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard let tab = tab(for: webView) else { return }

        tab.errorMessage = nil
        tab.hasAttemptedNavigation = true

        if activeTabID == tab.id {
            errorMessage = nil
            hasAttemptedNavigation = true
            isLoading = true
            estimatedProgress = max(0.08, webView.estimatedProgress)
            resetScreenshotForNavigation()
            resetXHRTracking(for: webView.url)
        }

        syncPageState(from: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let tab = tab(for: webView) else { return }

        tab.errorMessage = nil
        tab.navigationFallbacks = []

        if activeTabID == tab.id {
            errorMessage = nil
            navigationFallbacks = []
        }

        syncPageState(from: webView)

        if let url = webView.url {
            recordVisitedURL(url, identityID: tab.identityID)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let tab = tab(for: webView) else { return }

        tab.errorMessage = nil

        if activeTabID == tab.id {
            errorMessage = nil
            estimatedProgress = 1
        }

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
        handleNavigationError(error, in: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
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

        if let browserWebView = webView as? BrowserWKWebView {
            browserWebView.configureForcedDarkPageBackground(settingsStore.usesDarkMode(for: url))
        }
        decisionHandler(.allow)
    }

    private func handleNavigationError(_ error: Error, in webView: WKWebView) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }

        guard let tab = tab(for: webView) else { return }
        tab.navigationFallbacks = []
        tab.errorMessage = error.localizedDescription

        if activeTabID == tab.id {
            navigationFallbacks = []
            isLoading = false
            estimatedProgress = 0
            errorMessage = error.localizedDescription
            finishScreenshotWaiters(with: .failure(error))
        }

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

        if activeTabID == tab.id {
            navigationFallbacks = tab.navigationFallbacks
            errorMessage = nil
            displayAddressText = nextURL.absoluteString
            isSecurePage = nextURL.scheme?.lowercased() == "https"
            resetXHRTracking(for: nextURL)
        }

        webView.load(URLRequest(url: nextURL))
        return true
    }
}

extension BrowserModel: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }

        return nil
    }
}
