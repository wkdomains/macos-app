//
//  BrowserTitlebarTabs.swift
//  macos-app
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct BrowserTitlebarTab: Identifiable, Equatable {
    var id: UUID
    var title: String
    var url: URL?
    var isActive: Bool
    var isLoading: Bool
    var isPinned: Bool
    var hasAttemptedNavigation: Bool
}

extension BrowserWKWebView {
    func removeTitlebarTabsAccessory() {
        guard let titlebarTabsAccessory else { return }
        removeTitlebarTabsAccessory(titlebarTabsAccessory, from: titlebarTabsWindow)
        self.titlebarTabsAccessory = nil
        titlebarTabsWindow = nil
    }


    func updateTitlebarTabsAccessory() {
        guard let window else {
            removeTitlebarTabsAccessory()
            return
        }

        let accessory: BrowserTabsTitlebarAccessoryViewController
        if let existingAccessory = titlebarTabsAccessory {
            accessory = existingAccessory
            if titlebarTabsWindow !== window {
                removeTitlebarTabsAccessory(existingAccessory, from: titlebarTabsWindow)
                existingAccessory.tabs = titlebarTabs
                existingAccessory.selectTab = { [weak self] tabID in
                    self?.selectTab?(tabID)
                }
                existingAccessory.addTab = { [weak self] in
                    self?.addTab?()
                }
                existingAccessory.moveTab = { [weak self] sourceID, targetID in
                    self?.moveTab?(sourceID, targetID)
                }
                existingAccessory.togglePinnedTab = { [weak self] tabID in
                    self?.togglePinnedTab?(tabID)
                }
                window.addTitlebarAccessoryViewController(existingAccessory)
                titlebarTabsWindow = window
            }
        } else {
            accessory = BrowserTabsTitlebarAccessoryViewController()
            accessory.layoutAttribute = .left
            accessory.tabs = titlebarTabs
            accessory.selectTab = { [weak self] tabID in
                self?.selectTab?(tabID)
            }
            accessory.addTab = { [weak self] in
                self?.addTab?()
            }
            accessory.moveTab = { [weak self] sourceID, targetID in
                self?.moveTab?(sourceID, targetID)
            }
            accessory.togglePinnedTab = { [weak self] tabID in
                self?.togglePinnedTab?(tabID)
            }
            titlebarTabsAccessory = accessory
            window.addTitlebarAccessoryViewController(accessory)
            titlebarTabsWindow = window
        }

        accessory.tabs = titlebarTabs
        accessory.selectTab = { [weak self] tabID in
            self?.selectTab?(tabID)
        }
        accessory.addTab = { [weak self] in
            self?.addTab?()
        }
        accessory.moveTab = { [weak self] sourceID, targetID in
            self?.moveTab?(sourceID, targetID)
        }
        accessory.togglePinnedTab = { [weak self] tabID in
            self?.togglePinnedTab?(tabID)
        }
    }

    private func removeTitlebarTabsAccessory(
        _ accessory: BrowserTabsTitlebarAccessoryViewController,
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

final class BrowserTabsTitlebarAccessoryViewController: NSTitlebarAccessoryViewController {
    var tabs: [BrowserTitlebarTab] = [] {
        didSet {
            guard oldValue != tabs else { return }
            renderButtons()
        }
    }

    var selectTab: ((UUID) -> Void)?
    var addTab: (() -> Void)?
    var moveTab: ((UUID, UUID) -> Void)?
    var togglePinnedTab: ((UUID) -> Void)?

    private static var cachedFavicons: [String: NSImage] = [:]
    private static var requestedFavicons = Set<String>()
    private static var failedFavicons = Set<String>()
    private static let faviconDidUpdate = Notification.Name("BrowserTabsTitlebarFaviconDidUpdate")
    private let pinnedTabWidth: CGFloat = 32
    private let preferredNormalTabWidth: CGFloat = 216
    private let minimumNormalTabWidth: CGFloat = 116
    private let newTabButtonWidth: CGFloat = 28
    private let buttonSpacing: CGFloat = 4
    private let horizontalInset: CGFloat = 8
    private let accessoryHeight: CGFloat = 28
    private static let faviconPointSize: CGFloat = 16
    private static let faviconPixelSize = 32
    private var hostingView: BrowserTabsTitlebarHostingView?
    private var faviconObserver: NSObjectProtocol?
    private let dragState = BrowserTabsDragState()

    deinit {
        if let faviconObserver {
            NotificationCenter.default.removeObserver(faviconObserver)
        }
    }

    override func loadView() {
        let hostingView = BrowserTabsTitlebarHostingView(rootView: BrowserTabsTitlebarView(
            items: [],
            dragState: dragState,
            selectTab: { _ in },
            addTab: {},
            moveTab: { _, _ in },
            togglePinnedTab: { _ in }
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 0, height: accessoryHeight)
        hostingView.sizingOptions = []
        self.hostingView = hostingView
        view = hostingView
        observeFaviconUpdates()
    }

    private func observeFaviconUpdates() {
        guard faviconObserver == nil else { return }

        faviconObserver = NotificationCenter.default.addObserver(
            forName: Self.faviconDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.renderButtons()
        }
    }

    private func renderButtons() {
        loadViewIfNeeded()

        let tabWidth = normalTabWidth(for: tabs)

        let items = tabs.map { tab in
            BrowserTitlebarItem(
                id: tab.id,
                title: titlebarTitle(for: tab),
                image: tab.url.flatMap { favicon(for: $0) } ?? placeholderImage(),
                tooltip: titlebarTooltip(for: tab),
                isActive: tab.isActive,
                isLoading: tab.isLoading,
                isPinned: tab.isPinned,
                width: tab.isPinned ? pinnedTabWidth : tabWidth
            )
        }

        view.setFrameSize(NSSize(width: accessoryWidth(for: items), height: accessoryHeight))

        hostingView?.rootView = BrowserTabsTitlebarView(
            items: items,
            dragState: dragState,
            selectTab: { [weak self] tabID in
                self?.selectTab?(tabID)
            },
            addTab: { [weak self] in
                self?.addTab?()
            },
            moveTab: { [weak self] sourceID, targetID in
                self?.moveTab?(sourceID, targetID)
            },
            togglePinnedTab: { [weak self] tabID in
                self?.togglePinnedTab?(tabID)
            }
        )
    }

    private func favicon(for url: URL) -> NSImage? {
        let cacheKey = Self.faviconCacheKey(for: url)
        if let image = Self.cachedFavicons[cacheKey] {
            return image
        }

        requestFavicon(for: url)
        return nil
    }

    private func requestFavicon(for url: URL) {
        let cacheKey = Self.faviconCacheKey(for: url)
        guard !Self.failedFavicons.contains(cacheKey),
              Self.requestedFavicons.insert(cacheKey).inserted,
              !Self.faviconURLs(for: url).isEmpty
        else {
            return
        }

        Task {
            var loadedImageData: Data?

            for faviconURL in Self.faviconURLs(for: url) {
                guard let imageData = try? await Self.fetchData(from: faviconURL) else {
                    continue
                }

                let isUsableImage = await MainActor.run {
                    Self.faviconImage(from: imageData) != nil
                }

                if isUsableImage {
                    loadedImageData = imageData
                    break
                }
            }

            await MainActor.run {
                if let loadedImageData, let image = Self.faviconImage(from: loadedImageData) {
                    Self.cachedFavicons[cacheKey] = image
                } else {
                    Self.failedFavicons.insert(cacheKey)
                }

                NotificationCenter.default.post(name: Self.faviconDidUpdate, object: nil)
                renderButtons()
            }
        }
    }

    private func placeholderImage() -> NSImage? {
        NSImage(named: NSImage.Name("AppIcon"))
            ?? NSImage(systemSymbolName: "globe", accessibilityDescription: "Tab")
    }

    private func titlebarTooltip(for tab: BrowserTitlebarTab) -> String {
        guard let url = tab.url else {
            return tab.hasAttemptedNavigation ? tab.title : "New Tab"
        }

        guard let host = url.host else {
            return url.absoluteString
        }

        let path = url.path.isEmpty || url.path == "/" ? "" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        let fragment = url.fragment.map { "#\($0)" } ?? ""
        let title = tab.title == BrowserWKWebView.defaultWindowTitle ? host : tab.title
        return "\(title) - \(host)\(path)\(query)\(fragment)"
    }

    private func titlebarTitle(for tab: BrowserTitlebarTab) -> String {
        guard !tab.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              tab.title != BrowserWKWebView.defaultWindowTitle
        else {
            return tab.url?.host ?? "New Tab"
        }

        return tab.title
    }

    private static func faviconCacheKey(for url: URL) -> String {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased()
        else {
            return url.absoluteString
        }

        var key = "\(scheme)://\(host)"
        if let port = url.port {
            key += ":\(port)"
        }

        return key
    }

    private static func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)

        if let response = response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            throw URLError(.badServerResponse)
        }

        return data
    }

    private static func faviconURLs(for url: URL) -> [URL] {
        [rootFaviconURL(for: url), googleFaviconURL(for: url)].compactMap { $0 }
    }

    private static func rootFaviconURL(for url: URL) -> URL? {
        guard let scheme = url.scheme,
              let host = url.host
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        components.path = "/favicon.ico"
        return components.url
    }

    private static func googleFaviconURL(for url: URL) -> URL? {
        guard var components = URLComponents(string: "https://www.google.com/s2/favicons") else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "domain_url", value: url.absoluteString),
            URLQueryItem(name: "sz", value: String(faviconPixelSize))
        ]

        return components.url
    }

    private static func faviconImage(from data: Data) -> NSImage? {
        guard let image = NSImage(data: data) else { return nil }

        let preferredPixels = faviconPixelSize
        let bestRepresentation = image.representations
            .filter { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }
            .min { first, second in
                representationScore(first, preferredPixels: preferredPixels)
                    < representationScore(second, preferredPixels: preferredPixels)
            }

        guard let bestRepresentation,
              let preparedRepresentation = bestRepresentation.copy() as? NSImageRep
        else {
            let preparedImage = (image.copy() as? NSImage) ?? image
            preparedImage.size = NSSize(width: faviconPointSize, height: faviconPointSize)
            return preparedImage
        }

        preparedRepresentation.size = NSSize(width: faviconPointSize, height: faviconPointSize)

        let preparedImage = NSImage(size: NSSize(width: faviconPointSize, height: faviconPointSize))
        preparedImage.addRepresentation(preparedRepresentation)
        preparedImage.isTemplate = image.isTemplate
        return preparedImage
    }

    private static func representationScore(_ representation: NSImageRep, preferredPixels: Int) -> Int {
        let pixels = max(representation.pixelsWide, representation.pixelsHigh)
        let undersizedPenalty = pixels < preferredPixels ? preferredPixels : 0
        return undersizedPenalty + abs(pixels - preferredPixels)
    }

    private func normalTabWidth(for tabs: [BrowserTitlebarTab]) -> CGFloat {
        let normalCount = tabs.filter { !$0.isPinned }.count
        guard normalCount > 0 else { return preferredNormalTabWidth }

        let pinnedCount = tabs.count - normalCount
        let windowWidth = view.window?.frame.width ?? 1000
        let maximumAccessoryWidth = max(360, min(windowWidth - 240, 980))
        let spacingCount = max(0, tabs.count)
        let fixedWidth = (horizontalInset * 2)
            + newTabButtonWidth
            + (CGFloat(spacingCount) * buttonSpacing)
            + (CGFloat(pinnedCount) * pinnedTabWidth)
        let availableNormalWidth = max(
            minimumNormalTabWidth,
            (maximumAccessoryWidth - fixedWidth) / CGFloat(normalCount)
        )
        return min(preferredNormalTabWidth, max(minimumNormalTabWidth, availableNormalWidth))
    }

    private func accessoryWidth(for items: [BrowserTitlebarItem]) -> CGFloat {
        let itemWidth = items.reduce(CGFloat(0)) { partialResult, item in
            partialResult + item.width
        }
        let itemCount = items.count + 1
        let spacing = CGFloat(max(0, itemCount - 1)) * buttonSpacing
        return (horizontalInset * 2) + itemWidth + newTabButtonWidth + spacing
    }
}

private struct BrowserTitlebarItem: Identifiable {
    let id: UUID
    let title: String
    let image: NSImage?
    let tooltip: String
    let isActive: Bool
    let isLoading: Bool
    let isPinned: Bool
    let width: CGFloat
}

private final class BrowserTabsDragState {
    var draggingTabID: UUID?
    var dropTargetTabID: UUID?
}

private final class BrowserTabsTitlebarHostingView: NSHostingView<BrowserTabsTitlebarView> {
    override var mouseDownCanMoveWindow: Bool {
        false
    }
}

private struct BrowserTabsTitlebarView: View {
    let items: [BrowserTitlebarItem]
    let dragState: BrowserTabsDragState
    let selectTab: (UUID) -> Void
    let addTab: () -> Void
    let moveTab: (UUID, UUID) -> Void
    let togglePinnedTab: (UUID) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                Button {
                    selectTab(item.id)
                } label: {
                    TabIcon(item: item)
                }
                .buttonStyle(.plain)
                .help(item.tooltip)
                .contextMenu {
                    Button(item.isPinned ? "Unpin Tab" : "Pin Tab") {
                        togglePinnedTab(item.id)
                    }
                }
                .onDrag {
                    dragState.dropTargetTabID = nil
                    dragState.draggingTabID = item.id
                    return NSItemProvider(object: item.id.uuidString as NSString)
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: BrowserTitlebarTabDropDelegate(
                        item: item,
                        dragState: dragState,
                        moveTab: moveTab
                    )
                )
            }

            Button(action: addTab) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab")
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
    }
}

private struct BrowserTitlebarTabDropDelegate: DropDelegate {
    let item: BrowserTitlebarItem
    let dragState: BrowserTabsDragState
    let moveTab: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingTabID = dragState.draggingTabID,
              draggingTabID != item.id
        else {
            return
        }

        dragState.dropTargetTabID = item.id
    }

    func dropExited(info: DropInfo) {
        if dragState.dropTargetTabID == item.id {
            dragState.dropTargetTabID = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggingTabID = dragState.draggingTabID else {
            dragState.dropTargetTabID = nil
            return true
        }
        let targetTabID = dragState.dropTargetTabID ?? item.id
        dragState.draggingTabID = nil
        dragState.dropTargetTabID = nil

        guard draggingTabID != targetTabID else {
            return true
        }

        DispatchQueue.main.async {
            moveTab(draggingTabID, targetTabID)
        }
        return true
    }
}

private struct TabIcon: View {
    let item: BrowserTitlebarItem

    var body: some View {
        Group {
            if item.isPinned {
                pinnedIcon
            } else {
                normalTab
            }
        }
        .frame(width: item.width, height: 24)
        .contentShape(Rectangle())
    }

    private var pinnedIcon: some View {
        ZStack {
            tabBackground
            favicon
        }
    }

    private var normalTab: some View {
        HStack(spacing: 7) {
            favicon
            Text(item.title)
                .font(.system(size: 12, weight: item.isActive ? .semibold : .medium))
                .foregroundStyle(item.isActive ? Color.primary : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .background(tabBackground)
    }

    private var tabBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(item.isActive ? Color.primary.opacity(0.12) : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(item.isActive ? Color.primary.opacity(0.13) : Color.clear, lineWidth: 1)
            }
    }

    private var favicon: some View {
        Group {
            if item.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.55)
                    .frame(width: 16, height: 16)
            } else if let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 16, height: 16)
    }
}
