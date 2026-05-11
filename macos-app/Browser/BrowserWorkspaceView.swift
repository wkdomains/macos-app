//
//  BrowserWorkspaceView.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import AppKit
import SwiftUI
import WebKit

extension ContentView {
    var browserWorkspace: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                browserContent
                    .frame(width: isBotPanelVisible ? proxy.size.width * 0.75 : proxy.size.width)

                if isBotPanelVisible {
                    BotTerminalPanel(terminal: browser.botTerminal)
                        .frame(width: proxy.size.width * 0.25)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeInOut(duration: 0.18), value: isBotPanelVisible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var browserContent: some View {
        ZStack {
            Color(nsColor: browser.viewportMode == .desktop ? .textBackgroundColor : .windowBackgroundColor)

            ZStack {
                BrowserWebViewStack(
                    tabs: browser.tabStates,
                    activeTabID: browser.activeTabID,
                    blocksProgrammaticFocus: isAddressFocused || isPageFindFocused
                )

                if !browser.hasAttemptedNavigation {
                    EmptyBrowserState()
                }

                if let errorMessage = browser.errorMessage {
                    BrowserErrorState(message: errorMessage) {
                        browser.reload()
                    }
                }

                if isPageFindVisible {
                    pageFindBar
                        .padding(.top, 12)
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(width: browser.viewportMode.width)
            .frame(
                maxWidth: browser.viewportMode == .desktop ? .infinity : nil,
                maxHeight: .infinity
            )
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var pageFindBar: some View {
        HStack(spacing: 6) {
            PageFindTextField(
                text: $pageFindDraft,
                isFocused: $isPageFindFocused,
                selectAllOnFocus: $shouldSelectPageFindText,
                onSubmit: { findPageText(backwards: false) },
                onSubmitBackwards: { findPageText(backwards: true) },
                onCancel: hidePageFindBar
            )
            .frame(minWidth: 140, maxWidth: 220, minHeight: 30, maxHeight: 30)
            .layoutPriority(1)

            if let pageFindMatchFound {
                Text(pageFindMatchFound ? "Found" : "No results")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(pageFindMatchFound ? .secondary : Color(nsColor: .systemRed))
                    .frame(width: 62, alignment: .leading)
            }

            Button {
                findPageText(backwards: true)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(pageFindDraft.isEmpty)
            .foregroundStyle(pageFindDraft.isEmpty ? .tertiary : .primary)
            .accessibilityLabel("Previous match")
            .help("Previous match")

            Button {
                findPageText(backwards: false)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(pageFindDraft.isEmpty)
            .foregroundStyle(pageFindDraft.isEmpty ? .tertiary : .primary)
            .accessibilityLabel("Next match")
            .help("Next match")

            Button {
                hidePageFindBar()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close find")
            .help("Close find")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 38)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        )
    }

    var viewportControls: some View {
        HStack(spacing: 1) {
            ForEach(BrowserViewportMode.allCases) { mode in
                Button {
                    browser.setViewportMode(mode)
                } label: {
                    Image(systemName: mode.systemName)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(browser.viewportMode == mode ? Color.accentColor : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(browser.viewportMode == mode ? Color.accentColor.opacity(0.14) : Color.clear)
                )
                .overlay {
                    if pulsingViewportMode == mode {
                        ViewportPulseRing()
                            .id(viewportPulseToken)
                    }
                }
                .accessibilityLabel(mode.accessibilityLabel)
                .help(mode.helpText)
            }
        }
        .onChange(of: browser.viewportMode) { _, mode in
            pulseViewportControl(mode)
        }
    }

    func pulseViewportControl(_ mode: BrowserViewportMode) {
        let token = UUID()
        viewportPulseToken = token
        pulsingViewportMode = mode

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard viewportPulseToken == token else { return }
            pulsingViewportMode = nil
        }
    }

    var botControls: some View {
        HStack(spacing: 1) {
            Button {
                if isBotPanelVisible {
                    isBotPanelVisible = false
                    browser.closeBotTerminal()
                } else {
                    isBotPanelVisible = true
                    browser.requestLLMSSummary()
                }
            } label: {
                Image(systemName: "memorychip")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isBotPanelVisible ? Color.accentColor : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isBotPanelVisible ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .accessibilityLabel("Bot panel")
            .help("Bot panel")
        }
    }

    var progressBar: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.35))
                .frame(height: 1)

            if browser.isLoading && browser.estimatedProgress > 0.02 && browser.estimatedProgress < 0.72 {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.7))
                        .frame(width: max(24, proxy.size.width * browser.estimatedProgress), height: 2)
                        .animation(.easeOut(duration: 0.18), value: browser.estimatedProgress)
                }
                .frame(height: 2)
                .transition(.opacity)
            }
        }
        .frame(height: 2)
    }

    func showPageFindBar() {
        hideSuggestions()
        isAddressEditing = false
        isAddressFocused = false
        isPageFindVisible = true
        isPageFindFocused = true
        shouldSelectPageFindText = true
        shouldFocusBrowserAfterLoad = false

        if !pageFindDraft.isEmpty {
            findPageText()
        }
    }

    func hidePageFindBar() {
        isPageFindFocused = false
        isPageFindVisible = false
        pageFindMatchFound = nil
        browser.clearPageFind()
        focusBrowserContent()
    }

    func findPageText(backwards: Bool = false) {
        guard isPageFindVisible else { return }

        if pageFindDraft.isEmpty {
            pageFindMatchFound = nil
            browser.clearPageFind()
            return
        }

        let query = pageFindDraft
        browser.findInPage(query, backwards: backwards) { matchFound in
            guard pageFindDraft == query else { return }
            pageFindMatchFound = matchFound
        }
    }
}

private struct ViewportPulseRing: View {
    @State private var isExpanded = false

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .stroke(Color.accentColor.opacity(isExpanded ? 0 : 0.9), lineWidth: 2)
            .scaleEffect(isExpanded ? 1.24 : 1)
            .animation(.easeOut(duration: 0.55), value: isExpanded)
            .onAppear {
                isExpanded = true
            }
    }
}

struct BrowserToolbarButton: View {
    let systemName: String
    let accessibilityLabel: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? .tertiary : .primary)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct PageFindTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var selectAllOnFocus: Bool

    let onSubmit: () -> Void
    let onSubmitBackwards: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> BrowserPageFindNSTextField {
        let textField = BrowserPageFindNSTextField()
        textField.delegate = context.coordinator
        textField.onKeyDown = { event in
            context.coordinator.handleKeyDown(event)
        }
        textField.placeholderString = "Find in page"
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.sendsActionOnEndEditing = false

        return textField
    }

    func updateNSView(_ nsView: BrowserPageFindNSTextField, context: Context) {
        context.coordinator.parent = self

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        guard isFocused else { return }

        DispatchQueue.main.async {
            guard nsView.window != nil,
                  nsView.window?.firstResponder !== nsView.currentEditor()
            else {
                context.coordinator.selectAllIfNeeded(in: nsView)
                return
            }

            nsView.window?.makeFirstResponder(nsView)
            context.coordinator.selectAllIfNeeded(in: nsView)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PageFindTextField

        init(_ parent: PageFindTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true

            if let textField = notification.object as? BrowserPageFindNSTextField {
                DispatchQueue.main.async {
                    self.selectAllIfNeeded(in: textField)
                }
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }

            parent.selectAllOnFocus = false
            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    parent.onSubmitBackwards()
                } else {
                    parent.onSubmit()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }

        func handleKeyDown(_ event: NSEvent) -> Bool {
            let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if event.keyCode == 53 {
                parent.onCancel()
                return true
            }

            guard event.keyCode == 36 || event.keyCode == 76 else {
                return false
            }

            if modifierFlags.subtracting(.shift).isEmpty {
                modifierFlags.contains(.shift) ? parent.onSubmitBackwards() : parent.onSubmit()
                return true
            }

            return false
        }

        func selectAllIfNeeded(in textField: BrowserPageFindNSTextField) {
            guard parent.selectAllOnFocus,
                  let editor = textField.currentEditor()
            else {
                return
            }

            parent.selectAllOnFocus = false
            editor.selectAll(nil)
        }
    }
}

private final class BrowserPageFindNSTextField: NSTextField {
    var onKeyDown: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true {
            return
        }

        super.keyDown(with: event)
    }
}
