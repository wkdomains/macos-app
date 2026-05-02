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
    private var contextMenuEventMonitor: Any?

    deinit {
        if let contextMenuEventMonitor {
            NSEvent.removeMonitor(contextMenuEventMonitor)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeContextMenuEventMonitor()
        } else {
            installContextMenuEventMonitor()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        browserContextMenu()
    }

    private func installContextMenuEventMonitor() {
        guard contextMenuEventMonitor == nil else { return }

        contextMenuEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }

            let isContextClick = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))

            guard isContextClick,
                  self.shouldHandleContextMenuEvent(event)
            else {
                return event
            }

            NSMenu.popUpContextMenu(self.browserContextMenu(), with: event, for: self)
            self.window?.invalidateCursorRects(for: self)
            return nil
        }
    }

    private func removeContextMenuEventMonitor() {
        guard let contextMenuEventMonitor else { return }
        NSEvent.removeMonitor(contextMenuEventMonitor)
        self.contextMenuEventMonitor = nil
    }

    private func shouldHandleContextMenuEvent(_ event: NSEvent) -> Bool {
        guard event.window === window,
              isHidden == false,
              alphaValue > 0
        else {
            return false
        }

        let point = convert(event.locationInWindow, from: nil)
        return bounds.contains(point)
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
}
