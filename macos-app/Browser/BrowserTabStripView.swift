//
//  BrowserTabStripView.swift
//  macos-app
//

import AppKit
import Foundation
import SwiftUI

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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
