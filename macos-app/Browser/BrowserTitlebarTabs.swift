//
//  BrowserTitlebarTabs.swift
//  macos-app
//

import AppKit
import SwiftUI
import WebKit

struct BrowserTitlebarTab: Identifiable, Equatable {
    var id: UUID
    var title: String
    var url: URL?
    var isActive: Bool
    var isLoading: Bool
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
            renderButtons()
        }
    }

    var selectTab: ((UUID) -> Void)?
    var addTab: (() -> Void)?

    private var cachedFavicons: [String: NSImage] = [:]
    private var requestedFavicons = Set<String>()
    private var failedFavicons = Set<String>()
    private let buttonSize: CGFloat = 24
    private let buttonSpacing: CGFloat = 4
    private let horizontalInset: CGFloat = 8
    private let accessoryHeight: CGFloat = 28
    private static let faviconPointSize: CGFloat = 16
    private static let faviconPixelSize = 32
    private var hostingView: BrowserTabsTitlebarHostingView?

    override func loadView() {
        let hostingView = BrowserTabsTitlebarHostingView(rootView: BrowserTabsTitlebarView(
            items: [],
            selectTab: { _ in },
            addTab: {}
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 0, height: accessoryHeight)
        hostingView.sizingOptions = []
        self.hostingView = hostingView
        view = hostingView
    }

    private func renderButtons() {
        loadViewIfNeeded()

        let width = accessoryWidth(for: tabs.count)
        view.setFrameSize(NSSize(width: width, height: accessoryHeight))

        let items = tabs.map { tab in
            BrowserTitlebarItem(
                id: tab.id,
                image: tab.url.flatMap { favicon(for: $0) } ?? placeholderImage(),
                tooltip: titlebarTooltip(for: tab),
                isActive: tab.isActive,
                isLoading: tab.isLoading
            )
        }

        hostingView?.rootView = BrowserTabsTitlebarView(
            items: items,
            selectTab: { [weak self] tabID in
                self?.selectTab?(tabID)
            },
            addTab: { [weak self] in
                self?.addTab?()
            }
        )
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
                    cachedFavicons[rawURL] = image
                } else {
                    failedFavicons.insert(rawURL)
                }

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

    private func accessoryWidth(for tabCount: Int) -> CGFloat {
        let itemCount = tabCount + 1
        let spacing = CGFloat(max(0, itemCount - 1)) * buttonSpacing
        return (horizontalInset * 2) + (CGFloat(itemCount) * buttonSize) + spacing
    }
}

private struct BrowserTitlebarItem: Identifiable {
    let id: UUID
    let image: NSImage?
    let tooltip: String
    let isActive: Bool
    let isLoading: Bool
}

private final class BrowserTabsTitlebarHostingView: NSHostingView<BrowserTabsTitlebarView> {
    override var mouseDownCanMoveWindow: Bool {
        false
    }
}

private struct BrowserTabsTitlebarView: View {
    let items: [BrowserTitlebarItem]
    let selectTab: (UUID) -> Void
    let addTab: () -> Void

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
            }

            Button(action: addTab) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab")
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
    }
}

private struct TabIcon: View {
    let item: BrowserTitlebarItem

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(item.isActive ? Color.accentColor.opacity(0.18) : Color.clear)

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
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
    }
}
