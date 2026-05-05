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

@MainActor
final class BrowserTabStripMouseEventBridge: ObservableObject {
    private var mouseDownHandler: ((CGPoint) -> Bool)?
    private var mouseDraggedHandler: ((CGPoint) -> Bool)?
    private var mouseUpHandler: ((CGPoint) -> Bool)?
    private var windowDragHandler: ((CGPoint) -> Bool)?
    private var cancelHandler: (() -> Void)?

    func configure(
        mouseDown: @escaping (CGPoint) -> Bool,
        mouseDragged: @escaping (CGPoint) -> Bool,
        mouseUp: @escaping (CGPoint) -> Bool,
        shouldDragWindow: @escaping (CGPoint) -> Bool,
        cancel: @escaping () -> Void
    ) {
        mouseDownHandler = mouseDown
        mouseDraggedHandler = mouseDragged
        mouseUpHandler = mouseUp
        windowDragHandler = shouldDragWindow
        cancelHandler = cancel
    }

    func clear() {
        mouseDownHandler = nil
        mouseDraggedHandler = nil
        mouseUpHandler = nil
        windowDragHandler = nil
        cancelHandler = nil
    }

    func mouseDown(at point: CGPoint) -> Bool {
        mouseDownHandler?(point) ?? false
    }

    func mouseDragged(to point: CGPoint) -> Bool {
        mouseDraggedHandler?(point) ?? false
    }

    func mouseUp(at point: CGPoint) -> Bool {
        mouseUpHandler?(point) ?? false
    }

    func shouldDragWindow(at point: CGPoint) -> Bool {
        windowDragHandler?(point) ?? false
    }

    func cancel() {
        cancelHandler?()
    }
}

struct BrowserTabStripView: View {
    let items: [BrowserTabItem]
    let selectTab: (UUID) -> Void
    let addTab: () -> Void
    let moveTab: (UUID, Int) -> Void
    let togglePinnedTab: (UUID) -> Void
    let mouseBridge: BrowserTabStripMouseEventBridge?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var faviconStore = BrowserTabStripFaviconStore()
    @StateObject private var dragState = BrowserTabStripDragState()
    @State private var tabFrames: [UUID: CGRect] = [:]
    private let trafficLightInset: CGFloat = 120
    private let trailingInset: CGFloat = 10
    private let tabStripHeight: CGFloat = 44
    private let tabHeight: CGFloat = 36
    private let tabSpacing: CGFloat = 4
    private let pinnedTabWidth: CGFloat = 36
    private let newTabWidth: CGFloat = 36
    private let minimumTabWidth: CGFloat = 76
    private let maximumTabWidth: CGFloat = 225
    private let dragActivationDistance: CGFloat = 5
    private static let coordinateSpaceName = "BrowserTabStripCoordinateSpace"

    var body: some View {
        GeometryReader { proxy in
            let tabWidth = normalTabWidth(for: proxy.size.width)

            HStack(spacing: tabSpacing) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        selectTab(item.id)
                    } label: {
                        BrowserTabStripItemView(
                            item: item,
                            favicon: faviconStore.image(for: item.url),
                            width: item.isPinned ? pinnedTabWidth : tabWidth,
                            height: tabHeight
                        )
                        .background(tabFrameReader(for: item.id))
                    }
                    .buttonStyle(.plain)
                    .offset(x: dragState.offset(for: item, at: index, spacing: tabSpacing))
                    .scaleEffect(dragState.draggingTabID == item.id ? 1.018 : 1)
                    .opacity(dragState.draggingTabID == item.id ? 0.97 : 1)
                    .shadow(
                        color: dragState.draggingTabID == item.id ? Color.black.opacity(0.28) : Color.clear,
                        radius: 9,
                        x: 0,
                        y: 5
                    )
                    .zIndex(dragState.draggingTabID == item.id ? 10 : 0)
                    .animation(reduceMotion ? nil : BrowserTabStripDragState.gapAnimation, value: dragState.dropIndex)
                    .help(tooltip(for: item))
                    .contextMenu {
                        Button(item.isPinned ? "Unpin Tab" : "Pin Tab") {
                            togglePinnedTab(item.id)
                        }
                    }
                    .gesture(tabDragGesture(for: item, at: index))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel(for: item))
                    .accessibilityAddTraits(item.isActive ? [.isButton, .isSelected] : [.isButton])
                    .accessibilityAction {
                        selectTab(item.id)
                    }
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
            .frame(width: proxy.size.width, height: tabStripHeight, alignment: .center)
            .coordinateSpace(name: Self.coordinateSpaceName)
            .onPreferenceChange(BrowserTabFramePreferenceKey.self) { frames in
                tabFrames = frames
                configureMouseBridge(with: frames)
            }
        }
        .frame(height: tabStripHeight)
        .background(BrowserChromeColors.tabStripBackground)
        .onAppear {
            configureMouseBridge(with: tabFrames)
        }
        .onChange(of: items) { _, _ in
            configureMouseBridge(with: tabFrames)
        }
        .onDisappear {
            mouseBridge?.clear()
            dragState.cancel()
        }
    }

    private func tabFrameReader(for tabID: UUID) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: BrowserTabFramePreferenceKey.self,
                value: [tabID: proxy.frame(in: .named(Self.coordinateSpaceName))]
            )
        }
    }

    private func tabDragGesture(for item: BrowserTabItem, at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                let layouts = dragLayouts()
                logTabDrag(
                    "changed tab=\(shortID(item.id)) title=\"\(title(for: item))\" translation=\(format(value.translation.width)),\(format(value.translation.height)) layouts=\(layouts.count) active=\(dragState.draggingTabID.map(shortID) ?? "nil")"
                )

                if dragState.draggingTabID == nil {
                    guard dragDistance(for: value) >= dragActivationDistance else {
                        logTabDrag(
                            "waiting-for-threshold tab=\(shortID(item.id)) distance=\(format(dragDistance(for: value))) threshold=\(format(dragActivationDistance))"
                        )
                        return
                    }

                    logTabDrag("begin tab=\(shortID(item.id)) index=\(index)")
                    dragState.beginDragging(item: item, at: index, layouts: layouts)
                }

                dragState.updateDragging(value: value, layouts: layouts, reduceMotion: reduceMotion)
            }
            .onEnded { _ in
                let result = dragState.dropResult()
                logTabDrag(
                    "ended tab=\(shortID(item.id)) result=\(result.map { "\(shortID($0.tabID))->\($0.dropIndex)" } ?? "nil")"
                )

                withAnimation(reduceMotion ? nil : BrowserTabStripDragState.settleAnimation) {
                    dragState.cancel()

                    if let result {
                        moveTab(result.tabID, result.dropIndex)
                    } else {
                        selectTab(item.id)
                    }
                }
            }
    }

    private func dragDistance(for value: DragGesture.Value) -> CGFloat {
        hypot(value.translation.width, value.translation.height)
    }

    private func logTabDrag(_ message: String) {
        NSLog("[wkdomains-tabs] \(message)")
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    private func dragLayouts() -> [BrowserTabDragLayoutItem] {
        dragLayouts(from: tabFrames)
    }

    private func dragLayouts(from frames: [UUID: CGRect]) -> [BrowserTabDragLayoutItem] {
        items.enumerated().compactMap { index, item in
            guard let frame = frames[item.id], frame.width > 0 else {
                return nil
            }

            return BrowserTabDragLayoutItem(
                id: item.id,
                index: index,
                isPinned: item.isPinned,
                frame: frame
            )
        }
    }

    private func configureMouseBridge(with frames: [UUID: CGRect]) {
        mouseBridge?.configure(
            mouseDown: { point in
                bridgeMouseDown(at: point, frames: frames)
            },
            mouseDragged: { point in
                bridgeMouseDragged(to: point, frames: frames)
            },
            mouseUp: { point in
                bridgeMouseUp(at: point, frames: frames)
            },
            shouldDragWindow: { point in
                bridgeShouldDragWindow(at: point, frames: frames)
            },
            cancel: {
                dragState.cancel()
            }
        )
    }

    private func bridgeMouseDown(at point: CGPoint, frames: [UUID: CGRect]) -> Bool {
        let layouts = dragLayouts(from: frames)
        guard let hitLayout = tabLayout(at: point, layouts: layouts),
              let item = items[safe: hitLayout.index]
        else {
            logTabDrag("bridge-down missed point=\(describe(point)) layouts=\(layouts.count)")
            return false
        }

        logTabDrag("bridge-down tab=\(shortID(item.id)) index=\(hitLayout.index) point=\(describe(point))")
        dragState.prepareDragging(item: item, at: hitLayout.index, startPoint: point)
        return true
    }

    private func bridgeMouseDragged(to point: CGPoint, frames: [UUID: CGRect]) -> Bool {
        guard let pendingTabID = dragState.pendingTabID else {
            return false
        }

        let layouts = dragLayouts(from: frames)
        let translation = dragState.pendingTranslation(to: point)
        logTabDrag(
            "bridge-drag tab=\(shortID(pendingTabID)) point=\(describe(point)) translation=\(format(translation.width)),\(format(translation.height)) layouts=\(layouts.count)"
        )
        dragState.updatePendingDrag(
            to: point,
            activationDistance: dragActivationDistance,
            layouts: layouts,
            reduceMotion: reduceMotion
        )
        return true
    }

    private func bridgeMouseUp(at point: CGPoint, frames: [UUID: CGRect]) -> Bool {
        guard let pendingTabID = dragState.pendingTabID else {
            return false
        }

        let layouts = dragLayouts(from: frames)
        dragState.updatePendingDrag(
            to: point,
            activationDistance: dragActivationDistance,
            layouts: layouts,
            reduceMotion: reduceMotion
        )

        let result = dragState.dropResult()
        logTabDrag(
            "bridge-up tab=\(shortID(pendingTabID)) result=\(result.map { "\(shortID($0.tabID))->\($0.dropIndex)" } ?? "nil")"
        )

        withAnimation(reduceMotion ? nil : BrowserTabStripDragState.settleAnimation) {
            dragState.cancel()

            if let result {
                moveTab(result.tabID, result.dropIndex)
            } else {
                selectTab(pendingTabID)
            }
        }
        return true
    }

    private func bridgeShouldDragWindow(at point: CGPoint, frames: [UUID: CGRect]) -> Bool {
        let layouts = dragLayouts(from: frames)
        guard tabLayout(at: point, layouts: layouts) == nil,
              !newTabFrame(from: layouts).insetBy(dx: -4, dy: -4).contains(point)
        else {
            return false
        }

        return point.y >= 0 && point.y <= tabStripHeight
    }

    private func tabLayout(
        at point: CGPoint,
        layouts: [BrowserTabDragLayoutItem]
    ) -> BrowserTabDragLayoutItem? {
        layouts.first { layout in
            layout.frame.insetBy(dx: 0, dy: -4).contains(point)
        }
    }

    private func newTabFrame(from layouts: [BrowserTabDragLayoutItem]) -> CGRect {
        let orderedLayouts = layouts.sorted { $0.index < $1.index }
        let minY = orderedLayouts.first?.frame.minY ?? ((tabStripHeight - tabHeight) / 2)
        let leadingX: CGFloat
        if let lastLayout = orderedLayouts.last {
            leadingX = lastLayout.frame.maxX + tabSpacing
        } else {
            leadingX = trafficLightInset
        }
        return CGRect(x: leadingX, y: minY, width: newTabWidth, height: tabHeight)
    }

    private func describe(_ point: CGPoint) -> String {
        "x=\(format(point.x)) y=\(format(point.y))"
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

    private func accessibilityLabel(for item: BrowserTabItem) -> String {
        let pinPrefix = item.isPinned ? "Pinned tab" : "Tab"
        let activeSuffix = item.isActive ? ", selected" : ""
        return "\(pinPrefix), \(title(for: item))\(activeSuffix)"
    }
}

struct BrowserNonDraggableChromeHost<Content: View>: NSViewRepresentable {
    private let content: Content
    private let mouseBridge: BrowserTabStripMouseEventBridge?
    private let height: CGFloat = 44

    init(
        mouseBridge: BrowserTabStripMouseEventBridge? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.mouseBridge = mouseBridge
        self.content = content()
    }

    func makeNSView(context: Context) -> BrowserNonDraggableChromeContainerView<Content> {
        BrowserNonDraggableChromeContainerView(
            rootView: content,
            height: height,
            mouseBridge: mouseBridge
        )
    }

    func updateNSView(_ nsView: BrowserNonDraggableChromeContainerView<Content>, context: Context) {
        nsView.update(rootView: content, mouseBridge: mouseBridge)
    }
}

final class BrowserNonDraggableChromeContainerView<Content: View>: NSView {
    private let preferredHeight: CGFloat
    private let hostingView: BrowserNonDraggableHostingView<Content>

    init(
        rootView: Content,
        height: CGFloat,
        mouseBridge: BrowserTabStripMouseEventBridge?
    ) {
        preferredHeight = height
        hostingView = BrowserNonDraggableHostingView(rootView: rootView)
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: height))

        wantsLayer = true
        hostingView.mouseBridge = mouseBridge
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.sizingOptions = []
        addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: preferredHeight)
    }

    override var fittingSize: NSSize {
        NSSize(width: super.fittingSize.width, height: preferredHeight)
    }

    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsetsZero
    }

    override var safeAreaRect: NSRect {
        bounds
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    func update(
        rootView: Content,
        mouseBridge: BrowserTabStripMouseEventBridge?
    ) {
        hostingView.rootView = rootView
        hostingView.mouseBridge = mouseBridge
        invalidateIntrinsicContentSize()
        hostingView.invalidateIntrinsicContentSize()
        needsLayout = true
    }
}

final class BrowserNonDraggableHostingView<Content: View>: NSHostingView<Content> {
    private let preferredHeight: CGFloat = 44
    var mouseBridge: BrowserTabStripMouseEventBridge?
    private var forwardsTabMouseEvents = false
    private var forwardedTabPoint: CGPoint?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: preferredHeight)
    }

    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsetsZero
    }

    override var safeAreaRect: NSRect {
        bounds
    }

    override var mouseDownCanMoveWindow: Bool {
        NSLog("[wkdomains-tabs] chrome-host mouseDownCanMoveWindow=false")
        return false
    }

    override func mouseDown(with event: NSEvent) {
        NSLog("[wkdomains-tabs] chrome-host mouseDown button=\(event.buttonNumber) location=\(Self.describe(event.locationInWindow))")
        let point = tabStripPoint(for: event)
        if event.buttonNumber == 0,
           mouseBridge?.mouseDown(at: point) == true {
            forwardsTabMouseEvents = true
            forwardedTabPoint = point
            trackForwardedTabDrag()
            return
        }

        if event.buttonNumber == 0,
           mouseBridge?.shouldDragWindow(at: point) == true {
            dragWindowManually(with: event)
            return
        }

        forwardsTabMouseEvents = false
        forwardedTabPoint = nil
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        NSLog("[wkdomains-tabs] chrome-host mouseDragged delta=\(Self.format(event.deltaX)),\(Self.format(event.deltaY))")
        if forwardsTabMouseEvents {
            _ = mouseBridge?.mouseDragged(to: forwardedPoint(byApplying: event))
            return
        }

        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        NSLog("[wkdomains-tabs] chrome-host mouseUp button=\(event.buttonNumber) location=\(Self.describe(event.locationInWindow))")
        if forwardsTabMouseEvents {
            forwardsTabMouseEvents = false
            _ = mouseBridge?.mouseUp(at: forwardedTabPoint ?? tabStripPoint(for: event))
            forwardedTabPoint = nil
            return
        }

        super.mouseUp(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            forwardsTabMouseEvents = false
            forwardedTabPoint = nil
            mouseBridge?.cancel()
        }
    }

    private func trackForwardedTabDrag() {
        guard let window else { return }

        while forwardsTabMouseEvents {
            guard let event = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp]
            ) else {
                break
            }

            switch event.type {
            case .leftMouseDragged:
                NSLog("[wkdomains-tabs] chrome-host mouseDragged delta=\(Self.format(event.deltaX)),\(Self.format(event.deltaY))")
                _ = mouseBridge?.mouseDragged(to: forwardedPoint(byApplying: event))
            case .leftMouseUp:
                NSLog("[wkdomains-tabs] chrome-host mouseUp button=\(event.buttonNumber) location=\(Self.describe(event.locationInWindow))")
                forwardsTabMouseEvents = false
                _ = mouseBridge?.mouseUp(at: forwardedTabPoint ?? tabStripPoint(for: event))
                forwardedTabPoint = nil
            default:
                break
            }
        }

        forwardsTabMouseEvents = false
        forwardedTabPoint = nil
    }

    private func forwardedPoint(byApplying event: NSEvent) -> CGPoint {
        var point = forwardedTabPoint ?? tabStripPoint(for: event)
        point.x += event.deltaX
        point.y -= event.deltaY
        forwardedTabPoint = point
        return point
    }

    private func dragWindowManually(with mouseDownEvent: NSEvent) {
        guard let window else { return }

        let initialMouseLocation = NSEvent.mouseLocation
        let initialWindowOrigin = window.frame.origin

        while true {
            guard let event = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp]
            ) else {
                return
            }

            switch event.type {
            case .leftMouseDragged:
                let currentMouseLocation = NSEvent.mouseLocation
                var nextOrigin = NSPoint(
                    x: initialWindowOrigin.x + currentMouseLocation.x - initialMouseLocation.x,
                    y: initialWindowOrigin.y + currentMouseLocation.y - initialMouseLocation.y
                )

                if let visibleFrame = window.screen?.visibleFrame {
                    nextOrigin.y = min(
                        nextOrigin.y,
                        visibleFrame.maxY - window.frame.height
                    )
                }

                window.setFrameOrigin(nextOrigin)
            case .leftMouseUp:
                return
            default:
                break
            }
        }
    }

    private func tabStripPoint(for event: NSEvent) -> CGPoint {
        let localPoint = convert(event.locationInWindow, from: nil)
        return CGPoint(x: localPoint.x, y: bounds.height - localPoint.y)
    }

    private static func describe(_ point: NSPoint) -> String {
        "x=\(format(point.x)) y=\(format(point.y))"
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
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
            if let favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else if item.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.64)
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
    private static let cacheLifetime: TimeInterval = 24 * 60 * 60

    init() {
        Self.createCacheDirectoryIfNeeded()
    }

    func image(for url: URL?) -> NSImage? {
        guard let url else { return nil }

        let key = Self.domainKey(for: url)
        if images[key] == nil {
            if let cachedImage = Self.cachedImage(for: key) {
                images[key] = cachedImage
                return cachedImage
            }

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

                Self.writeCachedData(data, for: cacheKey)
                images[cacheKey] = image
                return
            }

            failedURLs.insert(cacheKey)
        }
    }

    private static func domainKey(for url: URL) -> String {
        url.host?.lowercased() ?? url.absoluteString.lowercased()
    }

    private static func cachedImage(for cacheKey: String) -> NSImage? {
        let fileURL = cacheFileURL(for: cacheKey)
        guard isFreshCacheFile(at: fileURL),
              let data = try? Data(contentsOf: fileURL)
        else {
            return nil
        }

        return image(from: data)
    }

    private static func writeCachedData(_ data: Data, for cacheKey: String) {
        let fileURL = cacheFileURL(for: cacheKey)
        do {
            try ensureCacheDirectoryExists()
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Could not cache favicon for \(cacheKey): \(error.localizedDescription)")
        }
    }

    private static func ensureCacheDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: cacheDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private static func createCacheDirectoryIfNeeded() {
        do {
            try ensureCacheDirectoryExists()
        } catch {
            NSLog("Could not create favicon cache directory: \(error.localizedDescription)")
        }
    }

    private static func isFreshCacheFile(at fileURL: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modificationDate = attributes[.modificationDate] as? Date
        else {
            return false
        }

        return Date().timeIntervalSince(modificationDate) < cacheLifetime
    }

    private static var cacheDirectoryURL: URL {
        realHomeDirectoryURL(fileManager: .default)
            .appendingPathComponent(".cache/wkdomains/favicons", isDirectory: true)
    }

    private static func realHomeDirectoryURL(fileManager: FileManager) -> URL {
        guard let passwd = getpwuid(getuid()),
              let homePath = passwd.pointee.pw_dir
        else {
            return fileManager.homeDirectoryForCurrentUser
        }

        return URL(fileURLWithPath: String(cString: homePath), isDirectory: true)
    }

    private static func cacheFileURL(for cacheKey: String) -> URL {
        cacheDirectoryURL.appendingPathComponent("\(safeCacheFileName(for: cacheKey)).favicon")
    }

    private static func safeCacheFileName(for value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }
        return String(scalars.joined()).trimmingCharacters(in: CharacterSet(charactersIn: "."))
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

private struct BrowserTabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct BrowserTabDragLayoutItem {
    let id: UUID
    let index: Int
    let isPinned: Bool
    let frame: CGRect
}

private struct BrowserTabDragResult {
    let tabID: UUID
    let dropIndex: Int
}

private final class BrowserTabStripDragState: ObservableObject {
    static let gapAnimation = Animation.interactiveSpring(response: 0.18, dampingFraction: 0.86)
    static let settleAnimation = Animation.interactiveSpring(response: 0.22, dampingFraction: 0.88)

    @Published private(set) var draggingTabID: UUID?
    @Published private(set) var dropIndex: Int?
    @Published private var dragOffsetX: CGFloat = 0

    private var sourceIndex: Int?
    private var sourceIsPinned = false
    private var sourceFrame = CGRect.zero
    private var draggedWidth: CGFloat = 0
    private var pendingItem: BrowserTabItem?
    private var pendingIndex: Int?
    private var pendingStartPoint = CGPoint.zero

    var isDragging: Bool {
        draggingTabID != nil
    }

    var pendingTabID: UUID? {
        pendingItem?.id ?? draggingTabID
    }

    func prepareDragging(item: BrowserTabItem, at index: Int, startPoint: CGPoint) {
        cancel()
        pendingItem = item
        pendingIndex = index
        pendingStartPoint = startPoint
    }

    func pendingTranslation(to point: CGPoint) -> CGSize {
        CGSize(
            width: point.x - pendingStartPoint.x,
            height: point.y - pendingStartPoint.y
        )
    }

    func updatePendingDrag(
        to point: CGPoint,
        activationDistance: CGFloat,
        layouts: [BrowserTabDragLayoutItem],
        reduceMotion: Bool
    ) {
        guard let pendingItem,
              let pendingIndex
        else {
            return
        }

        let translation = pendingTranslation(to: point)
        if draggingTabID == nil {
            let distance = hypot(translation.width, translation.height)
            guard distance >= activationDistance else {
                NSLog(
                    "[wkdomains-tabs] bridge-waiting tab=\(String(pendingItem.id.uuidString.prefix(8))) distance=\(Self.format(distance)) threshold=\(Self.format(activationDistance))"
                )
                return
            }

            NSLog("[wkdomains-tabs] bridge-begin tab=\(String(pendingItem.id.uuidString.prefix(8))) index=\(pendingIndex)")
            beginDragging(item: pendingItem, at: pendingIndex, layouts: layouts)
        }

        updateDragging(
            translationWidth: translation.width,
            layouts: layouts,
            reduceMotion: reduceMotion
        )
    }

    func beginDragging(item: BrowserTabItem, at index: Int, layouts: [BrowserTabDragLayoutItem]) {
        guard draggingTabID == nil,
              let layout = layouts.first(where: { $0.id == item.id })
        else {
            NSLog("[wkdomains-tabs] begin-failed tab=\(String(item.id.uuidString.prefix(8))) index=\(index) layouts=\(layouts.count)")
            return
        }

        NSLog("[wkdomains-tabs] state-begin tab=\(String(item.id.uuidString.prefix(8))) index=\(index) frame=\(Self.describe(layout.frame))")
        draggingTabID = item.id
        sourceIndex = index
        sourceIsPinned = item.isPinned
        sourceFrame = layout.frame
        draggedWidth = layout.frame.width
        dropIndex = index + 1
        dragOffsetX = 0
    }

    func updateDragging(value: DragGesture.Value, layouts: [BrowserTabDragLayoutItem], reduceMotion: Bool) {
        updateDragging(
            translationWidth: value.translation.width,
            layouts: layouts,
            reduceMotion: reduceMotion
        )
    }

    private func updateDragging(
        translationWidth: CGFloat,
        layouts: [BrowserTabDragLayoutItem],
        reduceMotion: Bool
    ) {
        guard let draggingTabID,
              !layouts.isEmpty
        else {
            return
        }

        let groupLayouts = layouts
            .filter { $0.isPinned == sourceIsPinned }
            .sorted { $0.index < $1.index }

        guard let firstLayout = groupLayouts.first,
              let lastLayout = groupLayouts.last
        else {
            NSLog("[wkdomains-tabs] update-failed no-group-layouts dragging=\(String(draggingTabID.uuidString.prefix(8)))")
            return
        }

        let minimumOffset = firstLayout.frame.minX - sourceFrame.minX
        let maximumOffset = lastLayout.frame.maxX - sourceFrame.maxX
        let clampedOffset = min(max(translationWidth, minimumOffset), maximumOffset)
        dragOffsetX = clampedOffset

        let draggedMidX = sourceFrame.midX + clampedOffset
        let nextDropIndex = dropIndex(forDraggedMidX: draggedMidX, draggingTabID: draggingTabID, layouts: groupLayouts)
        guard nextDropIndex != dropIndex else {
            NSLog("[wkdomains-tabs] update-stable dragging=\(String(draggingTabID.uuidString.prefix(8))) offset=\(Self.format(clampedOffset)) dropIndex=\(dropIndex.map(String.init) ?? "nil")")
            return
        }

        NSLog("[wkdomains-tabs] update-drop-index dragging=\(String(draggingTabID.uuidString.prefix(8))) offset=\(Self.format(clampedOffset)) midX=\(Self.format(draggedMidX)) dropIndex=\(dropIndex.map(String.init) ?? "nil")->\(nextDropIndex)")
        guard !reduceMotion else {
            dropIndex = nextDropIndex
            return
        }

        withAnimation(Self.gapAnimation) {
            dropIndex = nextDropIndex
        }
    }

    func offset(for item: BrowserTabItem, at index: Int, spacing: CGFloat) -> CGFloat {
        guard let draggingTabID,
              let sourceIndex,
              let dropIndex,
              item.isPinned == sourceIsPinned
        else {
            return 0
        }

        if item.id == draggingTabID {
            return dragOffsetX
        }

        let gapWidth = draggedWidth + spacing
        if dropIndex > sourceIndex,
           index > sourceIndex,
           index < dropIndex {
            return -gapWidth
        }

        if dropIndex < sourceIndex,
           index >= dropIndex,
           index < sourceIndex {
            return gapWidth
        }

        return 0
    }

    func dropResult() -> BrowserTabDragResult? {
        guard let draggingTabID,
              let sourceIndex,
              let dropIndex
        else {
            return nil
        }

        let insertionIndex = sourceIndex < dropIndex ? dropIndex - 1 : dropIndex
        guard insertionIndex != sourceIndex else {
            return nil
        }

        return BrowserTabDragResult(tabID: draggingTabID, dropIndex: dropIndex)
    }

    func cancel() {
        draggingTabID = nil
        dropIndex = nil
        dragOffsetX = 0
        sourceIndex = nil
        sourceIsPinned = false
        sourceFrame = .zero
        draggedWidth = 0
        pendingItem = nil
        pendingIndex = nil
        pendingStartPoint = .zero
    }

    private func dropIndex(
        forDraggedMidX draggedMidX: CGFloat,
        draggingTabID: UUID,
        layouts: [BrowserTabDragLayoutItem]
    ) -> Int {
        var resolvedIndex = (layouts.last?.index ?? 0) + 1

        for layout in layouts where layout.id != draggingTabID {
            if draggedMidX <= layout.frame.midX {
                resolvedIndex = layout.index
                break
            }
        }

        return resolvedIndex
    }

    private static func describe(_ frame: CGRect) -> String {
        "x=\(format(frame.minX)) y=\(format(frame.minY)) w=\(format(frame.width)) h=\(format(frame.height))"
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
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
