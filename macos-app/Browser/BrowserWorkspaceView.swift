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
        browserContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var browserContent: some View {
        ZStack {
            Color(nsColor: browser.viewportMode == .desktop ? .textBackgroundColor : .windowBackgroundColor)

            BrowserXRayWorkspace(
                browser: browser,
                isVisible: isXRayModeVisible && browser.viewportMode == .desktop
            ) {
                browserPageSurface
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var browserPageSurface: some View {
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

            if browser.isConsolePanelVisible {
                BrowserConsolePanel(records: browser.consoleRecords) {
                    browser.setConsolePanelVisible(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
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
                browser.setConsolePanelVisible(!browser.isConsolePanelVisible)
            } label: {
                Image(systemName: "curlybraces.square")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(browser.isConsolePanelVisible ? Color.accentColor : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(browser.isConsolePanelVisible ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .accessibilityLabel("JavaScript console")
            .help("JavaScript console")

            Button {
                guard browser.viewportMode == .desktop else { return }
                isBotPanelVisible = false
                browser.closeBotTerminal()
                if isXRayModeVisible {
                    isXRayModeVisible = false
                } else {
                    isXRayModeVisible = true
                }
            } label: {
                Image(systemName: "memorychip")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(browser.viewportMode == .desktop ? (isXRayModeVisible ? .primary : .secondary) : .tertiary)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isXRayModeVisible && browser.viewportMode == .desktop ? Color.primary.opacity(0.12) : Color.clear)
            )
            .disabled(browser.viewportMode != .desktop)
            .accessibilityLabel("Terminator view")
            .help(browser.viewportMode == .desktop ? "Terminator view" : "Terminator view is available in desktop viewport")
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

private struct BrowserConsolePanel: View {
    let records: [ConsoleMessageRecord]
    let close: () -> Void

    private let tabs: [ConsoleToolbarTab] = [
        .init(systemName: "cursorarrow.rays", title: "Inspector", compactTitle: "Inspect"),
        .init(systemName: "chevron.right.square", title: "Console", compactTitle: "Console"),
        .init(systemName: "tag", title: "Debugger", compactTitle: "Debug"),
        .init(systemName: "arrow.up.arrow.down", title: "Network", compactTitle: "Net"),
        .init(systemName: "curlybraces", title: "Style Editor", compactTitle: "Style"),
        .init(systemName: "gauge.with.dots.needle.50percent", title: "Performance", compactTitle: "Perf")
    ]

    private let filters: [ConsoleFilter] = [
        .init(title: "Errors", compactTitle: "Err", isSelected: true),
        .init(title: "Warnings", compactTitle: "Warn", isSelected: true),
        .init(title: "Info", compactTitle: "Info", isSelected: true),
        .init(title: "Logs", compactTitle: "Logs", isSelected: true),
        .init(title: "Debug", compactTitle: "Debug", isSelected: true),
        .init(title: "CSS", compactTitle: "CSS", isSelected: false),
        .init(title: "XHR", compactTitle: "XHR", isSelected: false),
        .init(title: "Requests", compactTitle: "Req", isSelected: false)
    ]

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 640

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(tabs) { tab in
                                consoleTab(tab, isSelected: tab.title == "Console", isCompact: isCompact)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 8)

                    consoleIconButton(systemName: "rectangle.split.2x1", label: "Dock position", isCompact: isCompact)
                    consoleIconButton(systemName: "rectangle.on.rectangle", label: "Pop out", isCompact: isCompact)
                    consoleIconButton(systemName: "ellipsis", label: "More tools", isCompact: isCompact)

                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: isCompact ? 34 : 38, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Close JavaScript console")
                }
                .frame(height: 38)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 1)
                }

                HStack(spacing: 0) {
                    consoleIconButton(systemName: "trash", label: "Clear console", isCompact: isCompact)
                    Divider()

                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 13, weight: .medium))
                        Text("Filter Output")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, isCompact ? 10 : 12)
                    .layoutPriority(-1)

                    HStack(spacing: isCompact ? 3 : 4) {
                        ForEach(filters) { filter in
                            if filter.title == "CSS" {
                                Divider()
                                    .frame(height: 22)
                            }
                            filterChip(filter, isCompact: isCompact)
                        }
                    }
                    .padding(.trailing, isCompact ? 6 : 10)
                    .layoutPriority(1)

                    consoleIconButton(systemName: "gearshape", label: "Console settings", isCompact: isCompact)
                }
                .frame(height: 43)
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 1)
                }

                consoleOutput
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
    }

    private var consoleOutput: some View {
        VStack(alignment: .leading, spacing: 0) {
            if records.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Text(">>")
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                    Text("No page console messages captured yet.")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 14)
                .padding(.leading, 18)
            } else {
                ForEach(records.suffix(6), id: \.id) { record in
                    HStack(alignment: .top, spacing: 10) {
                        Text(record.level.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(color(for: record.level))
                            .frame(width: 48, alignment: .leading)
                        Text(record.message)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor).opacity(0.35))
                            .frame(height: 1)
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.82))
    }

    private func consoleTab(_ tab: ConsoleToolbarTab, isSelected: Bool, isCompact: Bool) -> some View {
        HStack(spacing: isCompact ? 7 : 8) {
            Image(systemName: tab.systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 18)
            Text(isCompact ? tab.compactTitle : tab.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(isSelected ? .primary : .secondary)
        .frame(height: 38)
        .padding(.horizontal, isCompact ? 9 : 13)
        .background(
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(height: 2)
                Spacer()
            }
        )
    }

    private func consoleIconButton(systemName: String, label: String, isCompact: Bool) -> some View {
        Button {} label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: isCompact ? 34 : 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
    }

    private func filterChip(_ filter: ConsoleFilter, isCompact: Bool) -> some View {
        Text(isCompact ? filter.compactTitle : filter.title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(filter.isSelected ? Color.accentColor : .secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, isCompact ? 7 : 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(filter.isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(filter.isSelected ? Color.accentColor : Color.clear)
                    .frame(height: 1)
            }
    }

    private func color(for level: String) -> Color {
        switch level.lowercased() {
        case "error":
            return Color(nsColor: .systemRed)
        case "warn", "warning":
            return Color(nsColor: .systemOrange)
        default:
            return .secondary
        }
    }
}

private struct ConsoleToolbarTab: Identifiable {
    var id: String { title }
    let systemName: String
    let title: String
    let compactTitle: String
}

private struct ConsoleFilter: Identifiable {
    var id: String { title }
    let title: String
    let compactTitle: String
    let isSelected: Bool
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
