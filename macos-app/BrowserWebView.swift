//
//  BrowserWebView.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import AppKit
import SwiftUI
import WebKit

struct BrowserWebView: NSViewRepresentable {
    let webView: BrowserWKWebView

    func makeNSView(context: Context) -> BrowserWKWebView {
        webView
    }

    func updateNSView(_ nsView: BrowserWKWebView, context: Context) {}
}

protocol BrowserContextMenuDelegate: AnyObject {
    func clearCookiesForCurrentDomain()
}

final class BrowserWKWebView: WKWebView {
    weak var browserContextMenuDelegate: BrowserContextMenuDelegate?
    var viewportSizeDidChange: (() -> Void)?
    private var lastReportedViewportSize = NSSize.zero

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportViewportSizeIfNeeded(newSize)
    }

    override func rightMouseDown(with event: NSEvent) {
        showBrowserContextMenu(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showBrowserContextMenu(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    private func showBrowserContextMenu(with event: NSEvent) {
        NSMenu.popUpContextMenu(browserContextMenu(), with: event, for: self)
        window?.invalidateCursorRects(for: self)
    }

    private func browserContextMenu() -> NSMenu {
        let menu = NSMenu()

        let reloadItem = NSMenuItem(
            title: "Reload",
            action: #selector(reloadFromContextMenu),
            keyEquivalent: ""
        )
        reloadItem.target = self
        menu.addItem(reloadItem)

        if url?.host != nil {
            let clearCookiesItem = NSMenuItem(
                title: "Clear cookies",
                action: #selector(clearCookiesFromContextMenu),
                keyEquivalent: ""
            )
            clearCookiesItem.target = self
            menu.addItem(clearCookiesItem)
        }

        return menu
    }

    @objc private func reloadFromContextMenu() {
        reload()
    }

    @objc private func clearCookiesFromContextMenu() {
        browserContextMenuDelegate?.clearCookiesForCurrentDomain()
    }

    private func reportViewportSizeIfNeeded(_ size: NSSize) {
        let didChange = abs(size.width - lastReportedViewportSize.width) >= 1
            || abs(size.height - lastReportedViewportSize.height) >= 1

        guard didChange else { return }
        lastReportedViewportSize = size
        viewportSizeDidChange?()
    }
}
