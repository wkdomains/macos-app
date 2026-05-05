//
//  BrowserTabStripMouseEventBridge.swift
//  macos-app
//

import Combine
import Foundation
import SwiftUI

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
