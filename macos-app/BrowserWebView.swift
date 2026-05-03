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
    func createFreshSiteIdentityForCurrentSite()
    func switchToSiteIdentity(_ menuItemID: String)
    func toggleDarkThemeForCurrentSite()
    func toggleBookmarkForCurrentPage()
    var siteIdentityMenuItems: [BrowserSiteIdentityMenuItem] { get }
    var currentIdentityName: String { get }
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
    var bookmarkURLs: [URL] = [] {
        didSet {
            updateBookmarkTitlebarAccessory()
        }
    }
    var openBookmark: ((URL) -> Void)?
    var viewportSizeDidChange: (() -> Void)?
    private var lastReportedViewportSize = NSSize.zero
    private var isHandlingDirectUserFocus = false
    private var contextMenuLinkURL: String?
    private var usesForcedDarkPageBackground = false
    private var bookmarkTitlebarAccessory: BookmarkTitlebarAccessoryViewController?
    private weak var bookmarkTitlebarWindow: NSWindow?

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
        updateBookmarkTitlebarAccessory()
    }

    func removeBookmarkTitlebarAccessory() {
        guard let bookmarkTitlebarAccessory else { return }
        removeBookmarkTitlebarAccessory(bookmarkTitlebarAccessory, from: bookmarkTitlebarWindow)
        self.bookmarkTitlebarAccessory = nil
        bookmarkTitlebarWindow = nil
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

        return menu
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

    @objc private func createFreshIdentityFromContextMenu() {
        browserContextMenuDelegate?.createFreshSiteIdentityForCurrentSite()
    }

    @objc private func switchIdentityFromContextMenu(_ sender: NSMenuItem) {
        guard let menuItemID = sender.representedObject as? String else { return }
        browserContextMenuDelegate?.switchToSiteIdentity(menuItemID)
    }

    @objc private func toggleDarkFromContextMenu() {
        browserContextMenuDelegate?.toggleDarkThemeForCurrentSite()
    }

    @objc private func toggleBookmarkFromContextMenu() {
        browserContextMenuDelegate?.toggleBookmarkForCurrentPage()
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

    private func updateBookmarkTitlebarAccessory() {
        guard let window else {
            removeBookmarkTitlebarAccessory()
            return
        }

        guard !bookmarkURLs.isEmpty else {
            removeBookmarkTitlebarAccessory()
            return
        }

        let accessory: BookmarkTitlebarAccessoryViewController
        if let existingAccessory = bookmarkTitlebarAccessory {
            accessory = existingAccessory
            if bookmarkTitlebarWindow !== window {
                removeBookmarkTitlebarAccessory(existingAccessory, from: bookmarkTitlebarWindow)
                window.addTitlebarAccessoryViewController(existingAccessory)
                bookmarkTitlebarWindow = window
            }
        } else {
            accessory = BookmarkTitlebarAccessoryViewController()
            accessory.layoutAttribute = .left
            bookmarkTitlebarAccessory = accessory
            window.addTitlebarAccessoryViewController(accessory)
            bookmarkTitlebarWindow = window
        }

        accessory.bookmarkURLs = bookmarkURLs
        accessory.openBookmark = { [weak self] url in
            self?.openBookmark?(url)
        }
    }

    private func removeBookmarkTitlebarAccessory(
        _ accessory: BookmarkTitlebarAccessoryViewController,
        from window: NSWindow?
    ) {
        guard let window,
              let index = window.titlebarAccessoryViewControllers.firstIndex(of: accessory)
        else {
            return
        }

        window.removeTitlebarAccessoryViewController(at: index)
    }
}

private final class BookmarkTitlebarAccessoryViewController: NSTitlebarAccessoryViewController {
    var bookmarkURLs: [URL] = [] {
        didSet {
            renderButtons()
        }
    }

    var openBookmark: ((URL) -> Void)?

    private let stackView = NSStackView()
    private var cachedFavicons: [String: NSImage] = [:]
    private var requestedFavicons = Set<String>()
    private var failedFavicons = Set<String>()

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 4
        stackView.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: container.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stackView.heightAnchor.constraint(greaterThanOrEqualToConstant: 28)
        ])

        view = container
    }

    private func renderButtons() {
        loadViewIfNeeded()

        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (index, url) in bookmarkURLs.enumerated() {
            let button = NSButton(frame: .zero)
            button.bezelStyle = .texturedRounded
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.image = favicon(for: url) ?? placeholderImage()
            button.target = self
            button.action = #selector(openBookmarkFromTitlebar(_:))
            button.tag = index
            button.toolTip = titlebarTooltip(for: url)
            button.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 24),
                button.heightAnchor.constraint(equalToConstant: 24)
            ])

            stackView.addArrangedSubview(button)
        }
    }

    private func favicon(for url: URL) -> NSImage? {
        let rawURL = url.absoluteString
        if let image = cachedFavicons[rawURL] {
            return image
        }

        requestFavicon(for: url)
        return nil
    }

    private func requestFavicon(for url: URL) {
        let rawURL = url.absoluteString
        guard !failedFavicons.contains(rawURL),
              requestedFavicons.insert(rawURL).inserted,
              let faviconURL = Self.faviconURL(for: url)
        else {
            return
        }

        Task {
            let imageData = try? await Self.fetchData(from: faviconURL)

            await MainActor.run {
                if let imageData, let image = NSImage(data: imageData) {
                    cachedFavicons[rawURL] = image
                } else {
                    failedFavicons.insert(rawURL)
                }

                renderButtons()
            }
        }
    }

    private func placeholderImage() -> NSImage? {
        NSImage(systemSymbolName: "globe", accessibilityDescription: "Bookmark")
    }

    private func titlebarTooltip(for url: URL) -> String {
        guard let host = url.host else {
            return url.absoluteString
        }

        let path = url.path.isEmpty || url.path == "/" ? "" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        let fragment = url.fragment.map { "#\($0)" } ?? ""
        return "\(host)\(path)\(query)\(fragment)"
    }

    @objc private func openBookmarkFromTitlebar(_ sender: NSButton) {
        guard bookmarkURLs.indices.contains(sender.tag) else { return }
        openBookmark?(bookmarkURLs[sender.tag])
    }

    private static func fetchData(from url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    private static func faviconURL(for url: URL) -> URL? {
        guard var components = URLComponents(string: "https://www.google.com/s2/favicons") else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "domain_url", value: url.absoluteString),
            URLQueryItem(name: "sz", value: "32")
        ]

        return components.url
    }
}
