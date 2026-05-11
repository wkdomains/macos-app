//
//  ContentView.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import AppKit
import Foundation
import SwiftUI

struct ContentView: View {
    @ObservedObject var browser: BrowserModel
    @State var addressDraft = ""
    @State var isAddressEditing = false
    @State var isAddressFocused = false
    @State var isBotPanelVisible = false
    @State var isPageFindFocused = false
    @State var isPageFindVisible = false
    @State var pageFindDraft = ""
    @State var pageFindMatchFound: Bool?
    @State var shouldSelectPageFindText = false
    @State var selectedSuggestionIndex: Int?
    @State var shouldSelectAddressText = false
    @State var shouldFocusBrowserAfterLoad = false
    @State var suggestionTask: Task<Void, Never>?
    @State var suggestions: [AddressSuggestion] = []
    @StateObject private var tabStripMouseBridge = BrowserTabStripMouseEventBridge()

    var body: some View {
        VStack(spacing: 0) {
            BrowserNonDraggableChromeHost(mouseBridge: tabStripMouseBridge) {
                BrowserTabStripView(
                    items: browser.tabs,
                    selectTab: { browser.selectTab($0) },
                    addTab: { browser.addEmptyTab() },
                    moveTab: { browser.moveTab($0, toDropIndex: $1) },
                    togglePinnedTab: { browser.togglePinnedTab($0) },
                    mouseBridge: tabStripMouseBridge
                )
                .frame(height: 44)
            }
            .frame(height: 44)
            .zIndex(20)

            browserToolbar
                .zIndex(10)
            progressBar

            browserWorkspace
                .zIndex(0)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowChromeConfigurator())
        .frame(minWidth: 720, minHeight: 520)
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .topLeading) {
            Button {
                focusAddressBar(selectAll: true)
            } label: {
                EmptyView()
            }
            .keyboardShortcut("l", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .overlay(alignment: .topLeading) {
            Button {
                showPageFindBar()
            } label: {
                EmptyView()
            }
            .keyboardShortcut("f", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .onAppear {
            addressDraft = browser.displayAddressText
            isAddressEditing = false
            isAddressFocused = false
            isPageFindFocused = false
            isPageFindVisible = false
            pageFindMatchFound = nil
            shouldSelectAddressText = false
            shouldSelectPageFindText = false
            shouldFocusBrowserAfterLoad = true
            hideSuggestions()
            focusBrowserContentWhenReady()
        }
        .onDisappear {
            suggestionTask?.cancel()
        }
        .onChange(of: addressDraft) { _, value in
            scheduleSuggestions(for: value)
        }
        .onChange(of: browser.displayAddressText) { _, value in
            guard !isAddressFocused else { return }
            addressDraft = value
        }
        .onChange(of: browser.historyURLs) { _, _ in
            scheduleSuggestions(for: addressDraft)
        }
        .onChange(of: browser.bookmarkURLs) { _, _ in
            scheduleSuggestions(for: addressDraft)
        }
        .onChange(of: browser.activeTabID) { _, _ in
            addressDraft = browser.displayAddressText
            hideSuggestions()
            pageFindMatchFound = nil
            if isPageFindVisible {
                DispatchQueue.main.async {
                    findPageText()
                }
            }

            if browser.hasAttemptedNavigation {
                isAddressEditing = false
                isAddressFocused = false
                shouldFocusBrowserAfterLoad = false
            } else {
                focusAddressBar(selectAll: false)
            }
        }
        .onChange(of: browser.isLoading) { _, isLoading in
            guard !isLoading else { return }

            if shouldFocusBrowserAfterLoad {
                focusPendingBrowserContent()
            }

            if isPageFindVisible, !pageFindDraft.isEmpty {
                findPageText()
            }
        }
        .onChange(of: browser.pageFindRequestID) { _, _ in
            showPageFindBar()
        }
        .onChange(of: pageFindDraft) { _, _ in
            findPageText()
        }
        .onChange(of: isAddressFocused) { _, isFocused in
            browser.webView.blocksProgrammaticFocus = isFocused || isPageFindFocused

            if isFocused {
                if shouldSelectAddressText || !shouldFocusBrowserAfterLoad {
                    shouldFocusBrowserAfterLoad = false
                }

                hideSuggestions()
                scheduleSuggestions(for: addressDraft)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    guard !isAddressFocused, !isAddressEditing else { return }
                    hideSuggestions()
                    addressDraft = browser.displayAddressText
                }
            }
        }
        .onChange(of: isPageFindFocused) { _, isFocused in
            browser.webView.blocksProgrammaticFocus = isFocused || isAddressFocused
        }
    }

    private var browserToolbar: some View {
        HStack(spacing: 6) {
            BrowserToolbarButton(
                systemName: "chevron.left",
                accessibilityLabel: "Back",
                isDisabled: !browser.canGoBack
            ) {
                browser.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)

            BrowserToolbarButton(
                systemName: "chevron.right",
                accessibilityLabel: "Forward",
                isDisabled: !browser.canGoForward
            ) {
                browser.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)

            BrowserToolbarButton(
                systemName: browser.isLoading ? "xmark" : "arrow.clockwise",
                accessibilityLabel: browser.isLoading ? "Stop loading" : "Reload",
                isDisabled: !browser.hasAttemptedNavigation && !browser.isLoading
            ) {
                browser.isLoading ? browser.stopLoading() : browser.reload()
            }
            .keyboardShortcut("r", modifiers: .command)

            addressBar

            viewportControls

            botControls
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(BrowserChromeColors.navigationBackground)
    }
}

enum BrowserChromeColors {
    static let tabStripBackground = Color(
        red: 31 / 255,
        green: 29 / 255,
        blue: 37 / 255
    )

    static let navigationBackground = Color(
        red: 43 / 255,
        green: 41 / 255,
        blue: 50 / 255
    )
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else { return }
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovable = false
        window.isMovableByWindowBackground = false
        positionTrafficLights(in: window)
        MainWindowFramePersistence.shared.attach(to: window)
    }

    private func positionTrafficLights(in window: NSWindow) {
        let xPositions: [NSWindow.ButtonType: CGFloat] = [
            .closeButton: 16,
            .miniaturizeButton: 39,
            .zoomButton: 62
        ]

        for (buttonType, xPosition) in xPositions {
            guard let button = window.standardWindowButton(buttonType),
                  let superview = button.superview
            else {
                continue
            }

            button.setFrameOrigin(NSPoint(
                x: xPosition,
                y: superview.bounds.height - 29
            ))
        }
    }
}

private final class MainWindowFramePersistence {
    static let shared = MainWindowFramePersistence()

    private var observations: [ObjectIdentifier: WindowObservation] = [:]
    private var appliedWindowIDs = Set<ObjectIdentifier>()

    private init() {}

    func attach(to window: NSWindow) {
        let windowID = ObjectIdentifier(window)

        if observations[windowID] == nil {
            observations[windowID] = WindowObservation(window: window) { [weak self, weak window] in
                guard let self,
                      let window
                else {
                    return
                }

                self.saveFrame(for: window)
            } onClose: { [weak self, weak window] in
                guard let self,
                      let window
                else {
                    return
                }

                self.saveFrame(for: window)
                self.observations.removeValue(forKey: ObjectIdentifier(window))
                self.appliedWindowIDs.remove(ObjectIdentifier(window))
            }
        }

        guard !appliedWindowIDs.contains(windowID) else { return }
        appliedWindowIDs.insert(windowID)
        restoreSavedFrameIfAvailable(to: window)
    }

    private func restoreSavedFrameIfAvailable(to window: NSWindow) {
        guard let savedFrame = AppSettingsStore.shared.startupMainWindowFrame else { return }

        let requestedFrame = NSRect(
            x: CGFloat(savedFrame.x),
            y: CGFloat(savedFrame.y),
            width: CGFloat(savedFrame.width),
            height: CGFloat(savedFrame.height)
        )
        window.setFrame(constrainedFrame(requestedFrame, for: window), display: false)
    }

    private func saveFrame(for window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen),
              !window.isMiniaturized
        else {
            return
        }

        let frame = window.frame
        AppSettingsStore.shared.updateMainWindowFrame(AppWindowFrame(
            x: Double(frame.origin.x),
            y: Double(frame.origin.y),
            width: Double(frame.width),
            height: Double(frame.height)
        ))
    }

    private func constrainedFrame(_ frame: NSRect, for window: NSWindow) -> NSRect {
        let minimumSize = window.minSize
        let width = max(frame.width, minimumSize.width)
        let height = max(frame.height, minimumSize.height)
        var candidate = NSRect(x: frame.minX, y: frame.minY, width: width, height: height)

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return candidate }

        let screen = screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(candidate).area < rhs.visibleFrame.intersection(candidate).area
        } ?? window.screen ?? NSScreen.main ?? screens[0]

        let visibleFrame = screen.visibleFrame
        candidate.size.width = min(candidate.width, visibleFrame.width)
        candidate.size.height = min(candidate.height, visibleFrame.height)

        if !visibleFrame.intersects(candidate) {
            candidate.origin.x = visibleFrame.midX - candidate.width / 2
            candidate.origin.y = visibleFrame.midY - candidate.height / 2
        }

        candidate.origin.x = min(max(candidate.minX, visibleFrame.minX), visibleFrame.maxX - candidate.width)
        candidate.origin.y = min(max(candidate.minY, visibleFrame.minY), visibleFrame.maxY - candidate.height)
        return candidate
    }
}

private final class WindowObservation {
    private var pendingSave: DispatchWorkItem?
    private var tokens: [NSObjectProtocol] = []

    init(
        window: NSWindow,
        onSave: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        let center = NotificationCenter.default
        let saveNotifications: [Notification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didEndLiveResizeNotification,
            NSWindow.didChangeScreenNotification
        ]

        tokens = saveNotifications.map { notificationName in
            center.addObserver(
                forName: notificationName,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleSave(onSave)
            }
        }

        tokens.append(center.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.pendingSave?.cancel()
            onClose()
        })
    }

    deinit {
        pendingSave?.cancel()
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func scheduleSave(_ save: @escaping () -> Void) {
        pendingSave?.cancel()

        let workItem = DispatchWorkItem(block: save)
        pendingSave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }
}

private extension NSRect {
    var area: CGFloat {
        guard !isNull,
              !isEmpty
        else {
            return 0
        }

        return width * height
    }
}

#Preview {
    ContentView(browser: BrowserModel())
}
