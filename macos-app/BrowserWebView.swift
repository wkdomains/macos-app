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
    let blocksProgrammaticFocus: Bool

    func makeNSView(context: Context) -> BrowserWKWebView {
        webView.blocksProgrammaticFocus = blocksProgrammaticFocus
        return webView
    }

    func updateNSView(_ nsView: BrowserWKWebView, context: Context) {
        nsView.blocksProgrammaticFocus = blocksProgrammaticFocus
    }
}

protocol BrowserContextMenuDelegate: AnyObject {
    func clearCookiesForCurrentDomain()
}

final class BrowserWKWebView: WKWebView {
    static let defaultWindowTitle = "wkdomains"

    weak var browserContextMenuDelegate: BrowserContextMenuDelegate?
    var blocksProgrammaticFocus = false
    var browserWindowTitle = BrowserWKWebView.defaultWindowTitle {
        didSet {
            window?.title = browserWindowTitle
        }
    }
    var viewportSizeDidChange: (() -> Void)?
    private var lastReportedViewportSize = NSSize.zero
    private var isHandlingDirectUserFocus = false
    private var contextMenuLinkURL: String?
    private var usesForcedDarkPageBackground = false

    override var acceptsFirstResponder: Bool {
        !blocksProgrammaticFocus || isHandlingDirectUserFocus
    }

    override func becomeFirstResponder() -> Bool {
        guard !blocksProgrammaticFocus || isHandlingDirectUserFocus else {
            return false
        }

        return super.becomeFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.title = browserWindowTitle
        configureDescendantScrollViewBackgrounds()
    }

    func configureForcedDarkPageBackground(_ enabled: Bool) {
        usesForcedDarkPageBackground = enabled

        let darkBackground = NSColor(
            calibratedRed: 24 / 255,
            green: 26 / 255,
            blue: 27 / 255,
            alpha: 1
        )

        wantsLayer = true
        layer?.backgroundColor = enabled ? darkBackground.cgColor : NSColor.clear.cgColor
        configureDescendantScrollViewBackgrounds()

        if #available(macOS 12.0, *) {
            underPageBackgroundColor = enabled ? darkBackground : nil
        }
    }

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
            allowDirectUserFocus {
                super.mouseDown(with: event)
            }
        }
    }

    func focusFromBrowserChrome() {
        blocksProgrammaticFocus = false
        guard !isLoading else {
            resignBrowserChromeFocus()
            return
        }

        guard window?.firstResponder !== self else { return }
        window?.makeFirstResponder(self)
    }

    func resignBrowserChromeFocus() {
        blocksProgrammaticFocus = false
    }

    private func allowDirectUserFocus(_ action: () -> Void) {
        isHandlingDirectUserFocus = true
        action()
        isHandlingDirectUserFocus = false
    }

    private func configureDescendantScrollViewBackgrounds() {
        setScrollViewBackgrounds(in: self)
    }

    private func setScrollViewBackgrounds(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.drawsBackground = !usesForcedDarkPageBackground
        }

        for subview in view.subviews {
            setScrollViewBackgrounds(in: subview)
        }
    }

    private func showBrowserContextMenu(with event: NSEvent) {
        resolveLinkURL(at: event) { [weak self, event] linkURL in
            guard let self else { return }

            contextMenuLinkURL = linkURL
            NSMenu.popUpContextMenu(browserContextMenu(), with: event, for: self)
            window?.invalidateCursorRects(for: self)
        }
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

        if let contextMenuLinkURL {
            let copyLinkItem = NSMenuItem(
                title: copyLinkMenuTitle(for: contextMenuLinkURL),
                action: #selector(copyLinkFromContextMenu(_:)),
                keyEquivalent: ""
            )
            copyLinkItem.target = self
            copyLinkItem.representedObject = contextMenuLinkURL
            menu.addItem(copyLinkItem)
        }

        return menu
    }

    private func copyLinkMenuTitle(for linkURL: String?) -> String {
        guard let linkURL else { return "Copy Link" }

        return "Copy \(truncatedMenuLinkTitle(linkURL))"
    }

    private func truncatedMenuLinkTitle(_ linkURL: String) -> String {
        let title = displayMenuLinkTitle(linkURL)
        guard title.count > 70 else { return title }
        return "\(title.prefix(67))..."
    }

    private func displayMenuLinkTitle(_ linkURL: String) -> String {
        guard let link = URL(string: linkURL),
              let host = link.host
        else {
            return linkURL
        }

        if link.host == url?.host {
            let path = link.path.isEmpty ? "/" : link.path
            let query = link.query.map { "?\($0)" } ?? ""
            let fragment = link.fragment.map { "#\($0)" } ?? ""
            return "\(path)\(query)\(fragment)"
        }

        let displayHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = link.path.isEmpty || link.path == "/" ? "" : link.path
        let query = link.query.map { "?\($0)" } ?? ""
        let fragment = link.fragment.map { "#\($0)" } ?? ""
        return "\(displayHost)\(path)\(query)\(fragment)"
    }

    private func resolveLinkURL(at event: NSEvent, completion: @escaping (String?) -> Void) {
        let point = convert(event.locationInWindow, from: nil)
        let x = max(0, min(bounds.width, point.x))
        let y = max(0, min(bounds.height, isFlipped ? point.y : bounds.height - point.y))
        let alternateY = max(0, min(bounds.height, isFlipped ? bounds.height - point.y : point.y))
        let script = """
        (() => {
          const points = [
            [\(Double(x)), \(Double(y))],
            [\(Double(x)), \(Double(alternateY))]
          ];

          const linkAt = (x, y) => {
            let element = document.elementFromPoint(x, y);

            while (element && element.shadowRoot) {
              const nested = element.shadowRoot.elementFromPoint(x, y);
              if (!nested || nested === element) break;
              element = nested;
            }

            const anchor = element && element.closest ? element.closest('a[href]') : null;
            return anchor ? (anchor.href || anchor.getAttribute('href') || null) : null;
          };

          for (const [x, y] of points) {
            const href = linkAt(x, y);
            if (href) return href;
          }

          return null;
        })()
        """

        evaluateJavaScript(script) { value, _ in
            let linkURL = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                completion(linkURL?.isEmpty == false ? linkURL : nil)
            }
        }
    }

    @objc private func reloadFromContextMenu() {
        reload()
    }

    @objc private func clearCookiesFromContextMenu() {
        browserContextMenuDelegate?.clearCookiesForCurrentDomain()
    }

    @objc private func copyLinkFromContextMenu(_ sender: NSMenuItem) {
        guard let linkURL = sender.representedObject as? String else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(linkURL, forType: .string)
        pasteboard.setString(linkURL, forType: .URL)
    }

    private func reportViewportSizeIfNeeded(_ size: NSSize) {
        let didChange = abs(size.width - lastReportedViewportSize.width) >= 1
            || abs(size.height - lastReportedViewportSize.height) >= 1

        guard didChange else { return }
        lastReportedViewportSize = size
        viewportSizeDidChange?()
    }
}
