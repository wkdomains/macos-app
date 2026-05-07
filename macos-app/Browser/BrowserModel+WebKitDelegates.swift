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
        logNavigationEvent("didStartProvisionalNavigation", webView: webView, tab: tab)

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
        logNavigationEvent("didCommit", webView: webView, tab: tab)

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
        logNavigationEvent("didFinish", webView: webView, tab: tab)

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

        if let browserWebView = webView as? BrowserWKWebView {
            browserWebView.configureForcedDarkPageBackground(settingsStore.usesDarkMode(for: url))
        }
        if navigationAction.targetFrame?.isMainFrame != false {
            BrowserDebugLogging.log(
                "[wkdomains-debug] navigation policy allow url=\(url.absoluteString) type=\(navigationAction.navigationType.rawValue) dark=\(settingsStore.usesDarkMode(for: url))"
            )
        }
        decisionHandler(.allow)
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
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = javascriptDialog(
            message: "Alert from \(displayHost(for: frame))",
            detail: message,
            style: .informational
        )
        alert.addButton(withTitle: "OK")

        present(alert, for: webView) { _ in
            completionHandler()
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = javascriptDialog(
            message: "Confirm action on \(displayHost(for: frame))",
            detail: message,
            style: .warning
        )
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        present(alert, for: webView) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let input = NSTextField(string: defaultText ?? "")
        input.lineBreakMode = .byTruncatingTail
        input.placeholderString = prompt
        input.frame = NSRect(x: 0, y: 0, width: 320, height: 24)

        let alert = javascriptDialog(
            message: "Prompt from \(displayHost(for: frame))",
            detail: prompt,
            style: .informational
        )
        alert.accessoryView = input
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        present(alert, for: webView) { response in
            completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let openPanel = NSOpenPanel()
        let choosesDirectories = parameters.allowsDirectories

        openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
        openPanel.canChooseDirectories = choosesDirectories
        openPanel.canChooseFiles = !choosesDirectories
        openPanel.canCreateDirectories = false
        openPanel.resolvesAliases = true
        openPanel.prompt = choosesDirectories ? "Choose Folder" : "Choose Files"
        openPanel.message = choosesDirectories
            ? "Choose a folder to upload."
            : "Choose files to upload."

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            completionHandler(response == .OK ? openPanel.urls : nil)
        }

        if let window = webView.window {
            openPanel.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(openPanel.runModal())
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil,
           let url = navigationAction.request.url {
            if let scheme = url.scheme?.lowercased(), ["http", "https", "about"].contains(scheme) {
                addTab(loading: url)
            } else {
                NSWorkspace.shared.open(url)
            }
        }

        return nil
    }

    private func javascriptDialog(message: String, detail: String, style: NSAlert.Style) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = style
        return alert
    }

    private func present(
        _ alert: NSAlert,
        for webView: WKWebView,
        completionHandler: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        if let window = webView.window {
            alert.beginSheetModal(for: window, completionHandler: completionHandler)
        } else {
            completionHandler(alert.runModal())
        }
    }

    private func displayHost(for frame: WKFrameInfo) -> String {
        frame.request.url?.host ?? webView.url?.host ?? "this page"
    }
}
