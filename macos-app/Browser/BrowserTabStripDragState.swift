//
//  BrowserTabStripDragState.swift
//  macos-app
//

import Combine
import Foundation
import SwiftUI

struct BrowserTabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct BrowserTabDragLayoutItem {
    let id: UUID
    let index: Int
    let isPinned: Bool
    let frame: CGRect
}

struct BrowserTabDragResult {
    let tabID: UUID
    let dropIndex: Int
}

final class BrowserTabStripDragState: ObservableObject {
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
