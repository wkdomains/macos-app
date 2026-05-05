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
    @State var selectedSuggestionIndex: Int?
    @State var shouldSelectAddressText = false
    @State var shouldFocusBrowserAfterLoad = false
    @State var suggestionTask: Task<Void, Never>?
    @State var suggestions: [AddressSuggestion] = []

    var body: some View {
        VStack(spacing: 0) {
            BrowserTabStripView(
                items: browser.tabs,
                selectTab: { browser.selectTab($0) },
                addTab: { browser.addEmptyTab() },
                moveTab: { browser.moveTab($0, to: $1) },
                togglePinnedTab: { browser.togglePinnedTab($0) }
            )
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
        .onAppear {
            addressDraft = browser.displayAddressText
            isAddressEditing = false
            isAddressFocused = false
            shouldSelectAddressText = false
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

            if browser.hasAttemptedNavigation {
                isAddressEditing = false
                isAddressFocused = false
                shouldFocusBrowserAfterLoad = true
                focusBrowserContentWhenReady()
            } else {
                focusAddressBar(selectAll: false)
            }
        }
        .onChange(of: browser.isLoading) { _, isLoading in
            guard shouldFocusBrowserAfterLoad, !isLoading else { return }
            focusPendingBrowserContent()
        }
        .onChange(of: isAddressFocused) { _, isFocused in
            browser.webView.blocksProgrammaticFocus = isFocused

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
        positionTrafficLights(in: window)
    }

    private func positionTrafficLights(in window: NSWindow) {
        let xPositions: [NSWindow.ButtonType: CGFloat] = [
            .closeButton: 16,
            .miniaturizeButton: 46,
            .zoomButton: 76
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

#Preview {
    ContentView(browser: BrowserModel())
}
