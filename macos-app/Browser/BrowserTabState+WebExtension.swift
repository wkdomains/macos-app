//
//  BrowserTabState+WebExtension.swift
//  macos-app
//

import Foundation
import WebKit

extension BrowserTabState: WKWebExtensionTab {
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        browserModel
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        browserModel?.tabStates.firstIndex { $0 === self } ?? NSNotFound
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        guard webView.configuration.webExtensionController === context.webExtensionController else { return nil }
        return webView
    }

    func title(for context: WKWebExtensionContext) -> String? {
        title
    }

    func isPinned(for context: WKWebExtensionContext) -> Bool {
        isPinned
    }

    func setPinned(_ pinned: Bool, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        browserModel?.setTab(id, pinned: pinned)
        completionHandler(nil)
    }

    func size(for context: WKWebExtensionContext) -> CGSize {
        webView.bounds.size
    }

    func url(for context: WKWebExtensionContext) -> URL? {
        webView.url
    }

    func pendingURL(for context: WKWebExtensionContext) -> URL? {
        pendingLoadRequest?.url ?? loadingURL ?? (webView.isLoading ? webView.url : nil)
    }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool {
        loadingURL == nil && !webView.isLoading
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        browserModel?.load(url, in: self, fallbackURLs: [])
        completionHandler(nil)
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if fromOrigin {
            webView.reloadFromOrigin()
        } else {
            webView.reload()
        }
        completionHandler(nil)
    }

    func goBack(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if webView.canGoBack {
            webView.goBack()
        }
        completionHandler(nil)
    }

    func goForward(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if webView.canGoForward {
            webView.goForward()
        }
        completionHandler(nil)
    }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        browserModel?.selectTab(id)
        completionHandler(nil)
    }

    func isSelected(for context: WKWebExtensionContext) -> Bool {
        browserModel?.activeTabID == id
    }

    func setSelected(_ selected: Bool, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if selected {
            browserModel?.selectTab(id)
        }
        completionHandler(nil)
    }

    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool {
        true
    }

    func shouldBypassPermissions(for context: WKWebExtensionContext) -> Bool {
        true
    }
}
