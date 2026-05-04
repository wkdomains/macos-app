//
//  BrowserTitlebarTabs.swift
//  macos-app
//

import AppKit
import Combine
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
        removeTitlebarTabsAccessory()
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
    private let pinnedTabWidth: CGFloat = 36
    private let preferredNormalTabWidth: CGFloat = 216
    private let minimumNormalTabWidth: CGFloat = 116
    private let newTabButtonWidth: CGFloat = 36
    private let buttonSpacing: CGFloat = 4
    private let horizontalInset: CGFloat = 8
    private let accessoryHeight: CGFloat = 40
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
        hostingView.preferredContentSize = NSSize(width: 0, height: accessoryHeight)
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

        let contentSize = NSSize(width: accessoryWidth(for: items), height: accessoryHeight)
        preferredContentSize = contentSize
        hostingView?.preferredContentSize = contentSize
        view.setFrameSize(contentSize)

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

struct BrowserTabStripView: View {
    let items: [BrowserTabItem]
    let selectTab: (UUID) -> Void
    let addTab: () -> Void
    let moveTab: (UUID, UUID) -> Void
    let togglePinnedTab: (UUID) -> Void

    @StateObject private var faviconStore = BrowserTabStripFaviconStore()
    private let trafficLightInset: CGFloat = 250
    private let trailingInset: CGFloat = 10
    private let tabStripHeight: CGFloat = 48
    private let tabHeight: CGFloat = 36
    private let tabSpacing: CGFloat = 4
    private let pinnedTabWidth: CGFloat = 36
    private let newTabWidth: CGFloat = 36
    private let minimumTabWidth: CGFloat = 76
    private let maximumTabWidth: CGFloat = 225
    private let dragState = BrowserTabStripDragState()

    var body: some View {
        GeometryReader { proxy in
            let tabWidth = normalTabWidth(for: proxy.size.width)

            HStack(spacing: tabSpacing) {
                ForEach(items) { item in
                    Button {
                        selectTab(item.id)
                    } label: {
                        BrowserTabStripItemView(
                            item: item,
                            favicon: faviconStore.image(for: item.url),
                            width: item.isPinned ? pinnedTabWidth : tabWidth,
                            height: tabHeight
                        )
                    }
                    .buttonStyle(.plain)
                    .help(tooltip(for: item))
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
                        delegate: BrowserContentTabDropDelegate(
                            item: item,
                            dragState: dragState,
                            moveTab: moveTab
                        )
                    )
                }

                Button(action: addTab) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: newTabWidth, height: tabHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New Tab")

                Spacer(minLength: 0)
            }
            .padding(.leading, trafficLightInset)
            .padding(.trailing, trailingInset)
            .frame(width: proxy.size.width, height: tabStripHeight, alignment: .leading)
        }
        .frame(height: tabStripHeight)
        .background(.bar)
    }

    private func normalTabWidth(for availableWidth: CGFloat) -> CGFloat {
        let normalCount = items.filter { !$0.isPinned }.count
        guard normalCount > 0 else { return maximumTabWidth }

        let pinnedCount = items.count - normalCount
        let spacingWidth = CGFloat(max(0, items.count)) * tabSpacing
        let fixedWidth = trafficLightInset
            + trailingInset
            + newTabWidth
            + spacingWidth
            + (CGFloat(pinnedCount) * pinnedTabWidth)
        let availableTabWidth = (availableWidth - fixedWidth) / CGFloat(normalCount)
        return min(maximumTabWidth, max(minimumTabWidth, availableTabWidth))
    }

    private func tooltip(for item: BrowserTabItem) -> String {
        guard let url = item.url else {
            return title(for: item)
        }

        guard let host = url.host else {
            return url.absoluteString
        }

        let path = url.path.isEmpty || url.path == "/" ? "" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        let fragment = url.fragment.map { "#\($0)" } ?? ""
        return "\(title(for: item)) - \(host)\(path)\(query)\(fragment)"
    }

    private func title(for item: BrowserTabItem) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }

        return item.url?.host ?? "New Tab"
    }
}

private struct BrowserTabStripItemView: View {
    let item: BrowserTabItem
    let favicon: NSImage?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            tabBackground

            if item.isPinned {
                faviconView
            } else {
                HStack(spacing: 9) {
                    faviconView
                    Text(title)
                        .font(.system(size: 13, weight: item.isActive ? .semibold : .medium))
                        .foregroundStyle(item.isActive ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 13)
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
    }

    private var title: String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }

        return item.url?.host ?? "New Tab"
    }

    private var tabBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(item.isActive ? selectedTabBackground : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(item.isActive ? Color.white.opacity(0.04) : Color.clear, lineWidth: 1)
            }
    }

    private var selectedTabBackground: Color {
        Color(
            red: 91 / 255,
            green: 89 / 255,
            blue: 102 / 255
        )
    }

    private var faviconView: some View {
        Group {
            if item.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.64)
            } else if let favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else if let image = NSImage(named: NSImage.Name("AppIcon")) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 18, height: 18)
    }
}

@MainActor
private final class BrowserTabStripFaviconStore: ObservableObject {
    @Published private var images: [String: NSImage] = [:]
    private var requestedURLs = Set<String>()
    private var failedURLs = Set<String>()

    func image(for url: URL?) -> NSImage? {
        guard let url else { return nil }

        let key = Self.cacheKey(for: url)
        if images[key] == nil {
            requestImage(for: url, cacheKey: key)
        }

        return images[key]
    }

    private func requestImage(for url: URL, cacheKey: String) {
        guard !failedURLs.contains(cacheKey),
              requestedURLs.insert(cacheKey).inserted
        else {
            return
        }

        Task {
            for faviconURL in Self.faviconURLs(for: url) {
                guard let data = try? await Self.fetchData(from: faviconURL),
                      let image = Self.image(from: data)
                else {
                    continue
                }

                images[cacheKey] = image
                return
            }

            failedURLs.insert(cacheKey)
        }
    }

    private static func cacheKey(for url: URL) -> String {
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
            URLQueryItem(name: "sz", value: "32")
        ]

        return components.url
    }

    private static func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)

        if let response = response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            throw URLError(.badServerResponse)
        }

        return data
    }

    private static func image(from data: Data) -> NSImage? {
        guard let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

private final class BrowserTabStripDragState {
    var draggingTabID: UUID?
    var dropTargetTabID: UUID?
}

private struct BrowserContentTabDropDelegate: DropDelegate {
    let item: BrowserTabItem
    let dragState: BrowserTabStripDragState
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
    var preferredContentSize = NSSize.zero {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: NSSize {
        preferredContentSize
    }

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
                    .frame(width: 36, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab")
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .fixedSize(horizontal: false, vertical: true)
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
        .frame(width: item.width, height: 34)
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
                .font(.system(size: 13, weight: item.isActive ? .semibold : .medium))
                .foregroundStyle(item.isActive ? Color.primary : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .background(tabBackground)
    }

    private var tabBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(item.isActive ? Color.primary.opacity(0.12) : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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
