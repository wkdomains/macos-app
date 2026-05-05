//
//  BrowserTabStripChromeHost.swift
//  macos-app
//

import AppKit
import SwiftUI

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
