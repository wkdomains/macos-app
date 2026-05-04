//
//  BrowserWebView.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import AppKit
import SwiftUI
import WebKit

enum LoginFieldRole {
    case username
    case password
}

struct LoginFieldTarget: Codable, Equatable {
    var cssPath: String?
    var tag: String
    var type: String?
    var id: String?
    var name: String?
    var placeholder: String?
    var ariaLabel: String?
    var formIndex: Int?
    var fieldIndex: Int?
    var formAction: String?
    var formMethod: String?
    var value: String?

    var isUsableLoginField: Bool {
        ["input", "textarea", "select"].contains(tag.lowercased())
    }
}

struct XHRContextMenuItem: Equatable {
    let index: Int
    let title: String
}

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
    func createFreshSiteIdentityForCurrentSite()
    func switchToSiteIdentity(_ menuItemID: String)
    func useLoginFieldFromContextMenu(_ role: LoginFieldRole, target: LoginFieldTarget)
    func fillSavedLoginForCurrentSite()
    func toggleDarkThemeForCurrentSite()
    func toggleBookmarkForCurrentPage()
    func openXHRFromContextMenu(at index: Int)
    func writeCurrentPageFilesToTemporaryDirectory()
    var siteIdentityMenuItems: [BrowserSiteIdentityMenuItem] { get }
    var xhrContextMenuItems: [XHRContextMenuItem] { get }
    var currentIdentityName: String { get }
    var canFillSavedLoginForCurrentSite: Bool { get }
    var canToggleDarkThemeForCurrentSite: Bool { get }
    var currentSiteIsExcludedFromDarkTheme: Bool { get }
    var canBookmarkCurrentPage: Bool { get }
    var currentPageIsBookmarked: Bool { get }
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
    var titlebarTabs: [BrowserTitlebarTab] = [] {
        didSet {
            guard oldValue != titlebarTabs else { return }
            guard window != nil || titlebarTabsAccessory != nil else { return }
            updateTitlebarTabsAccessory()
        }
    }
    var selectTab: ((UUID) -> Void)?
    var addTab: (() -> Void)?
    var moveTab: ((UUID, UUID) -> Void)?
    var viewportSizeDidChange: (() -> Void)?
    private var lastReportedViewportSize = NSSize.zero
    private var isHandlingDirectUserFocus = false
    private var contextMenuLinkURL: String?
    private var contextMenuLoginField: LoginFieldTarget?
    private var usesForcedDarkPageBackground = false
    var titlebarTabsAccessory: BrowserTabsTitlebarAccessoryViewController?
    weak var titlebarTabsWindow: NSWindow?

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
        updateTitlebarTabsAccessory()
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
        resolveContextMenuTarget(at: event) { [weak self, event] linkURL, loginField in
            guard let self else { return }

            contextMenuLinkURL = linkURL
            contextMenuLoginField = loginField
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
            menu.addItem(NSMenuItem.separator())

            let currentIdentityItem = NSMenuItem(
                title: "Identity: \(browserContextMenuDelegate?.currentIdentityName ?? "Default")",
                action: nil,
                keyEquivalent: ""
            )
            currentIdentityItem.isEnabled = false
            menu.addItem(currentIdentityItem)

            let freshIdentityItem = NSMenuItem(
                title: "Open Fresh Identity",
                action: #selector(createFreshIdentityFromContextMenu),
                keyEquivalent: ""
            )
            freshIdentityItem.target = self
            menu.addItem(freshIdentityItem)

            let switchIdentityItem = NSMenuItem(title: "Switch Identity", action: nil, keyEquivalent: "")
            switchIdentityItem.submenu = identitySubmenu()
            menu.addItem(switchIdentityItem)

            menu.addItem(NSMenuItem.separator())

            let clearCookiesItem = NSMenuItem(
                title: "Clear cookies",
                action: #selector(clearCookiesFromContextMenu),
                keyEquivalent: ""
            )
            clearCookiesItem.target = self
            menu.addItem(clearCookiesItem)

            menu.addItem(NSMenuItem.separator())

            if let contextMenuLoginField {
                let usernameItem = NSMenuItem(
                    title: "Use as Login Username",
                    action: #selector(useLoginUsernameFromContextMenu),
                    keyEquivalent: ""
                )
                usernameItem.target = self
                usernameItem.isEnabled = contextMenuLoginField.isUsableLoginField
                menu.addItem(usernameItem)

                let passwordItem = NSMenuItem(
                    title: "Use as Login Password",
                    action: #selector(useLoginPasswordFromContextMenu),
                    keyEquivalent: ""
                )
                passwordItem.target = self
                passwordItem.isEnabled = contextMenuLoginField.isUsableLoginField
                menu.addItem(passwordItem)
            }

            let fillLoginItem = NSMenuItem(
                title: "Fill Saved Login",
                action: #selector(fillSavedLoginFromContextMenu),
                keyEquivalent: ""
            )
            fillLoginItem.target = self
            fillLoginItem.isEnabled = browserContextMenuDelegate?.canFillSavedLoginForCurrentSite == true
            menu.addItem(fillLoginItem)
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

        menu.addItem(NSMenuItem.separator())

        let toggleDarkItem = NSMenuItem(
            title: "Exclude from Dark",
            action: #selector(toggleDarkFromContextMenu),
            keyEquivalent: ""
        )
        toggleDarkItem.target = self
        toggleDarkItem.isEnabled = browserContextMenuDelegate?.canToggleDarkThemeForCurrentSite == true
        toggleDarkItem.state = browserContextMenuDelegate?.currentSiteIsExcludedFromDarkTheme == true ? .on : .off
        menu.addItem(toggleDarkItem)

        let toggleBookmarkItem = NSMenuItem(
            title: "Bookmarked",
            action: #selector(toggleBookmarkFromContextMenu),
            keyEquivalent: ""
        )
        toggleBookmarkItem.target = self
        toggleBookmarkItem.isEnabled = browserContextMenuDelegate?.canBookmarkCurrentPage == true
        toggleBookmarkItem.state = browserContextMenuDelegate?.currentPageIsBookmarked == true ? .on : .off
        menu.addItem(toggleBookmarkItem)

        menu.addItem(NSMenuItem.separator())

        let xhrItem = NSMenuItem(title: "XHR", action: nil, keyEquivalent: "")
        xhrItem.submenu = xhrSubmenu()
        menu.addItem(xhrItem)

        menu.addItem(NSMenuItem.separator())

        let writeFilesItem = NSMenuItem(
            title: "Write file to /tmp",
            action: #selector(writeFilesToTemporaryDirectoryFromContextMenu),
            keyEquivalent: ""
        )
        writeFilesItem.target = self
        menu.addItem(writeFilesItem)

        return menu
    }

    private func xhrSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let items = browserContextMenuDelegate?.xhrContextMenuItems ?? []

        guard !items.isEmpty else {
            let emptyItem = NSMenuItem(title: "No XHRs", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
            return submenu
        }

        for item in items {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(openXHRFromContextMenu(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = item.index
            submenu.addItem(menuItem)
        }

        return submenu
    }

    private func identitySubmenu() -> NSMenu {
        let submenu = NSMenu()
        let items = browserContextMenuDelegate?.siteIdentityMenuItems ?? [
            BrowserSiteIdentityMenuItem(id: BrowserSiteIdentityMenuItem.defaultID, title: "Default", isCurrent: true)
        ]

        for identity in items {
            let item = NSMenuItem(
                title: identity.title,
                action: #selector(switchIdentityFromContextMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = identity.id
            item.state = identity.isCurrent ? .on : .off
            submenu.addItem(item)
        }

        return submenu
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

    private func resolveContextMenuTarget(
        at event: NSEvent,
        completion: @escaping (_ linkURL: String?, _ loginField: LoginFieldTarget?) -> Void
    ) {
        let point = convert(event.locationInWindow, from: nil)
        let x = max(0, min(bounds.width, point.x))
        let y = max(0, min(bounds.height, isFlipped ? point.y : bounds.height - point.y))
        let alternateY = max(0, min(bounds.height, isFlipped ? bounds.height - point.y : point.y))
        let script = """
        (() => {
          const escapeCSS = (value) => {
            if (window.CSS && CSS.escape) return CSS.escape(value);
            return String(value).replace(/[^a-zA-Z0-9_-]/g, "\\\\$&");
          };

          const points = [
            [\(Double(x)), \(Double(y))],
            [\(Double(x)), \(Double(alternateY))]
          ];

          const elementAt = (x, y) => {
            let element = document.elementFromPoint(x, y);

            while (element && element.shadowRoot) {
              const nested = element.shadowRoot.elementFromPoint(x, y);
              if (!nested || nested === element) break;
              element = nested;
            }

            return element;
          };

          const cssPathFor = (element) => {
            if (!element || !element.tagName) return null;
            if (element.id) {
              const selector = `#${escapeCSS(element.id)}`;
              if (document.querySelectorAll(selector).length === 1) return selector;
            }

            const parts = [];
            let current = element;
            while (current && current.nodeType === Node.ELEMENT_NODE && current !== document.documentElement) {
              let part = current.tagName.toLowerCase();
              const name = current.getAttribute("name");
              const type = current.getAttribute("type");
              if (name) part += `[name="${escapeCSS(name)}"]`;
              if (type && current.tagName.toLowerCase() === "input") part += `[type="${escapeCSS(type)}"]`;

              const parent = current.parentElement;
              if (parent) {
                const sameTagSiblings = Array.from(parent.children)
                  .filter((child) => child.tagName === current.tagName);
                if (sameTagSiblings.length > 1) {
                  part += `:nth-of-type(${sameTagSiblings.indexOf(current) + 1})`;
                }
              }

              parts.unshift(part);
              const selector = parts.join(" > ");
              if (document.querySelectorAll(selector).length === 1) return selector;
              current = parent;
            }

            return parts.join(" > ") || null;
          };

          const fieldTargetFor = (element) => {
            const field = element && element.closest
              ? element.closest("input, textarea, select")
              : null;
            if (!field) return null;

            const form = field.form || field.closest("form");
            const formFields = form
              ? Array.from(form.querySelectorAll("input, textarea, select"))
              : Array.from(document.querySelectorAll("input, textarea, select"));

            return {
              cssPath: cssPathFor(field),
              tag: field.tagName.toLowerCase(),
              type: field.getAttribute("type") || null,
              id: field.getAttribute("id") || null,
              name: field.getAttribute("name") || null,
              placeholder: field.getAttribute("placeholder") || null,
              ariaLabel: field.getAttribute("aria-label") || null,
              formIndex: form ? Array.from(document.querySelectorAll("form")).indexOf(form) : null,
              fieldIndex: formFields.indexOf(field),
              formAction: form ? (form.action || null) : null,
              formMethod: form ? (form.method || "get").toUpperCase() : null,
              value: field.value || null
            };
          };

          const resultFor = (x, y) => {
            const element = elementAt(x, y);
            const anchor = element && element.closest ? element.closest('a[href]') : null;
            return {
              linkURL: anchor ? (anchor.href || anchor.getAttribute('href') || null) : null,
              field: fieldTargetFor(element)
            };
          };

          for (const [x, y] of points) {
            const result = resultFor(x, y);
            if (result.linkURL || result.field) return result;
          }

          return { linkURL: null, field: null };
        })()
        """

        evaluateJavaScript(script) { value, _ in
            let result = value as? [String: Any]
            let linkURL = (result?["linkURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let loginField = Self.loginFieldTarget(from: result?["field"])
            DispatchQueue.main.async {
                completion(linkURL?.isEmpty == false ? linkURL : nil, loginField)
            }
        }
    }

    private static func loginFieldTarget(from value: Any?) -> LoginFieldTarget? {
        guard let dictionary = value as? [String: Any],
              let tag = dictionary["tag"] as? String
        else {
            return nil
        }

        return LoginFieldTarget(
            cssPath: dictionary["cssPath"] as? String,
            tag: tag,
            type: dictionary["type"] as? String,
            id: dictionary["id"] as? String,
            name: dictionary["name"] as? String,
            placeholder: dictionary["placeholder"] as? String,
            ariaLabel: dictionary["ariaLabel"] as? String,
            formIndex: Self.intValue(from: dictionary["formIndex"]),
            fieldIndex: Self.intValue(from: dictionary["fieldIndex"]),
            formAction: dictionary["formAction"] as? String,
            formMethod: dictionary["formMethod"] as? String,
            value: dictionary["value"] as? String
        )
    }

    private static func intValue(from value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return nil
    }

    @objc private func reloadFromContextMenu() {
        reload()
    }

    @objc private func clearCookiesFromContextMenu() {
        browserContextMenuDelegate?.clearCookiesForCurrentDomain()
    }

    @objc private func createFreshIdentityFromContextMenu() {
        browserContextMenuDelegate?.createFreshSiteIdentityForCurrentSite()
    }

    @objc private func switchIdentityFromContextMenu(_ sender: NSMenuItem) {
        guard let menuItemID = sender.representedObject as? String else { return }
        browserContextMenuDelegate?.switchToSiteIdentity(menuItemID)
    }

    @objc private func useLoginUsernameFromContextMenu() {
        guard let contextMenuLoginField else { return }
        browserContextMenuDelegate?.useLoginFieldFromContextMenu(.username, target: contextMenuLoginField)
    }

    @objc private func useLoginPasswordFromContextMenu() {
        guard let contextMenuLoginField else { return }
        browserContextMenuDelegate?.useLoginFieldFromContextMenu(.password, target: contextMenuLoginField)
    }

    @objc private func fillSavedLoginFromContextMenu() {
        browserContextMenuDelegate?.fillSavedLoginForCurrentSite()
    }

    @objc private func toggleDarkFromContextMenu() {
        browserContextMenuDelegate?.toggleDarkThemeForCurrentSite()
    }

    @objc private func toggleBookmarkFromContextMenu() {
        browserContextMenuDelegate?.toggleBookmarkForCurrentPage()
    }

    @objc private func openXHRFromContextMenu(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        browserContextMenuDelegate?.openXHRFromContextMenu(at: index)
    }

    @objc private func copyLinkFromContextMenu(_ sender: NSMenuItem) {
        guard let linkURL = sender.representedObject as? String else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(linkURL, forType: .string)
        pasteboard.setString(linkURL, forType: .URL)
    }

    @objc private func writeFilesToTemporaryDirectoryFromContextMenu() {
        browserContextMenuDelegate?.writeCurrentPageFilesToTemporaryDirectory()
    }

    private func reportViewportSizeIfNeeded(_ size: NSSize) {
        let didChange = abs(size.width - lastReportedViewportSize.width) >= 1
            || abs(size.height - lastReportedViewportSize.height) >= 1

        guard didChange else { return }
        lastReportedViewportSize = size
        viewportSizeDidChange?()
    }


}
