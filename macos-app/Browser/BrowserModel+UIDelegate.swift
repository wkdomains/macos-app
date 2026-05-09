//
//  BrowserModel+UIDelegate.swift
//  macos-app
//

import AppKit
import WebKit

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
