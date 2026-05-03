//
//  ContentView.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import AppKit
import Foundation
import SwiftUI

private struct AddressSuggestion: Identifiable {
    enum Kind {
        case history(URL)
        case search
    }

    let id: String
    let title: String
    let kind: Kind
    let faviconURL: URL?

    var accessibilityLabel: String {
        switch kind {
        case .history:
            "Open \(title)"
        case .search:
            "Search \(title)"
        }
    }
}

private struct AddressHistorySuggestionMatch {
    let rank: Int
    let offset: Int
    let suggestion: AddressSuggestion
}

private struct AddressCompletion {
    let suggestion: AddressSuggestion
    let typedText: String
    let suffix: String
}

struct ContentView: View {
    @ObservedObject var browser: BrowserModel
    @FocusState private var isAddressFocused: Bool
    @State private var isBotPanelVisible = false
    @State private var selectedSuggestionIndex: Int?
    @State private var suggestionTask: Task<Void, Never>?
    @State private var suggestions: [AddressSuggestion] = []
    @State private var keyDownMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            browserToolbar
                .zIndex(10)
            progressBar

            browserWorkspace
                .zIndex(0)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            isAddressFocused = true
            installAddressKeyMonitor()
            selectAddressText()
        }
        .onDisappear {
            suggestionTask?.cancel()
            removeAddressKeyMonitor()
        }
        .onChange(of: browser.addressText) { _, value in
            scheduleSuggestions(for: value)
        }
        .onChange(of: browser.historyURLs) { _, _ in
            scheduleSuggestions(for: browser.addressText)
        }
        .onChange(of: isAddressFocused) { _, isFocused in
            if isFocused {
                selectAddressText()
                scheduleSuggestions(for: browser.addressText)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    guard !isAddressFocused else { return }
                    hideSuggestions()
                }
            }
        }
    }

    private var browserToolbar: some View {
        HStack(spacing: 8) {
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

            Button {
                hideSuggestions()
                isAddressFocused = false
                browser.loadCurrentAddress()
                focusBrowserContent()
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(browser.addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Go")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var addressBar: some View {
        HStack(spacing: 8) {
            Image(systemName: browser.isSecurePage ? "lock.fill" : "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(browser.isSecurePage ? .green : .secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            addressTextField

            if !browser.addressText.isEmpty {
                Button {
                    browser.addressText = ""
                    hideSuggestions()
                    isAddressFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear address")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isAddressFocused ? Color.accentColor.opacity(0.75) : Color(nsColor: .separatorColor).opacity(0.55),
                    lineWidth: isAddressFocused ? 1.5 : 1
                )
        )
        .overlay(alignment: .topLeading) {
            if shouldShowSuggestions {
                suggestionMenu
                    .offset(y: 44)
            }
        }
        .zIndex(20)
    }

    private var addressTextField: some View {
        ZStack(alignment: .leading) {
            if let addressCompletion {
                HStack(spacing: 0) {
                    Text(addressCompletion.typedText)
                        .foregroundStyle(.clear)

                    Text(addressCompletion.suffix)
                        .foregroundStyle(.primary)
                }
                .font(.system(size: 14))
                .lineLimit(1)
                .allowsHitTesting(false)
            }

            TextField("Search or enter a website", text: $browser.addressText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .disableAutocorrection(true)
                .focused($isAddressFocused)
                .onSubmit {
                    submitAddressField()
                }
                .accessibilityLabel("Website address")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var suggestionMenu: some View {
        VStack(spacing: 2) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                Button {
                    selectSuggestion(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        suggestionIcon(for: suggestion)

                        Text(suggestion.title)
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selectedSuggestionIndex == index ? Color.accentColor.opacity(0.16) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(suggestion.accessibilityLabel)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        )
    }

    private var shouldShowSuggestions: Bool {
        isAddressFocused && !suggestions.isEmpty
    }

    private var addressCompletion: AddressCompletion? {
        guard isAddressFocused,
              selectedSuggestionIndex == nil,
              let suggestion = suggestions.first,
              case .history = suggestion.kind
        else {
            return nil
        }

        let typedText = browser.addressText
        let trimmedTypedText = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTypedText.isEmpty,
              typedText == trimmedTypedText,
              suggestion.title.lowercased().hasPrefix(typedText.lowercased()),
              suggestion.title.count > typedText.count
        else {
            return nil
        }

        return AddressCompletion(
            suggestion: suggestion,
            typedText: typedText,
            suffix: String(suggestion.title.dropFirst(typedText.count))
        )
    }

    @ViewBuilder
    private func suggestionIcon(for suggestion: AddressSuggestion) -> some View {
        switch suggestion.kind {
        case .history:
            if let faviconURL = suggestion.faviconURL {
                AsyncImage(url: faviconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
        case .search:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
        }
    }

    private func scheduleSuggestions(for value: String) {
        suggestionTask?.cancel()
        selectedSuggestionIndex = nil

        let query = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAddressFocused, !query.isEmpty else {
            suggestions = []
            return
        }

        let historyURLs = browser.historyURLs

        suggestionTask = Task { [query, historyURLs] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            let historySuggestions = Self.historySuggestions(for: query, historyURLs: historyURLs)

            await MainActor.run {
                guard !Task.isCancelled,
                      isAddressFocused,
                      browser.addressText.trimmingCharacters(in: .whitespacesAndNewlines) == query
                else {
                    return
                }

                suggestions = historySuggestions
                selectedSuggestionIndex = nil
            }

            let fetchedSuggestions = await Self.fetchSuggestions(for: query)
            let combinedSuggestions = Self.combinedSuggestions(
                historySuggestions: historySuggestions,
                searchSuggestions: fetchedSuggestions
            )

            await MainActor.run {
                guard !Task.isCancelled,
                      isAddressFocused,
                      browser.addressText.trimmingCharacters(in: .whitespacesAndNewlines) == query
                else {
                    return
                }

                suggestions = combinedSuggestions
                selectedSuggestionIndex = nil
            }
        }
    }

    private func hideSuggestions() {
        suggestionTask?.cancel()
        suggestions = []
        selectedSuggestionIndex = nil
    }

    private func submitAddressField() {
        if let selectedSuggestionIndex,
           suggestions.indices.contains(selectedSuggestionIndex)
        {
            selectSuggestion(suggestions[selectedSuggestionIndex])
        } else if let addressCompletion {
            selectSuggestion(addressCompletion.suggestion)
        } else {
            hideSuggestions()
            isAddressFocused = false
            browser.loadCurrentAddress()
            focusBrowserContent()
        }
    }

    private func selectSuggestion(_ suggestion: AddressSuggestion) {
        hideSuggestions()
        isAddressFocused = false

        switch suggestion.kind {
        case .history(let url):
            browser.load(url)
        case .search:
            browser.searchGoogle(for: suggestion.title)
        }
        focusBrowserContent()
    }

    private func selectPreviousSuggestion() {
        guard shouldShowSuggestions else { return }

        if let selectedSuggestionIndex {
            self.selectedSuggestionIndex = selectedSuggestionIndex > 0
                ? selectedSuggestionIndex - 1
                : suggestions.count - 1
        } else {
            selectedSuggestionIndex = suggestions.count - 1
        }
    }

    private func selectNextSuggestion() {
        guard shouldShowSuggestions else { return }

        if let selectedSuggestionIndex {
            self.selectedSuggestionIndex = selectedSuggestionIndex < suggestions.count - 1
                ? selectedSuggestionIndex + 1
                : 0
        } else {
            selectedSuggestionIndex = 0
        }
    }

    private func installAddressKeyMonitor() {
        guard keyDownMonitor == nil else { return }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isAddressFocused, shouldShowSuggestions else { return event }

            switch event.keyCode {
            case 36, 76:
                submitAddressField()
                return nil
            case 53:
                hideSuggestions()
                return nil
            case 125:
                selectNextSuggestion()
                return nil
            case 126:
                selectPreviousSuggestion()
                return nil
            default:
                return event
            }
        }
    }

    private func selectAddressText() {
        for delay in [0.0, 0.06, 0.16] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard isAddressFocused,
                      let fieldEditor = NSApp.keyWindow?.firstResponder as? NSTextView
                else {
                    return
                }

                fieldEditor.selectAll(nil)
            }
        }
    }

    private func focusBrowserContent() {
        DispatchQueue.main.async {
            browser.webView.window?.makeFirstResponder(browser.webView)
        }
    }

    private func removeAddressKeyMonitor() {
        guard let keyDownMonitor else { return }

        NSEvent.removeMonitor(keyDownMonitor)
        self.keyDownMonitor = nil
    }

    private static func fetchSuggestions(for query: String) async -> [String] {
        guard var components = URLComponents(string: "https://www.google.com/complete/search") else {
            return []
        }

        components.queryItems = [
            URLQueryItem(name: "client", value: "firefox"),
            URLQueryItem(name: "q", value: query)
        ]

        guard let url = components.url else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let value = try JSONSerialization.jsonObject(with: data) as? [Any],
                  value.count > 1,
                  let suggestions = value[1] as? [String]
            else {
                return []
            }

            return Array(suggestions.prefix(10))
        } catch {
            return []
        }
    }

    private static func historySuggestions(for query: String, historyURLs: [String]) -> [AddressSuggestion] {
        let normalizedQuery = query.lowercased()
        var matches: [AddressHistorySuggestionMatch] = []

        for (offset, rawURL) in historyURLs.enumerated() {
            guard let url = URL(string: rawURL),
                  let rank = historyRank(for: url, normalizedQuery: normalizedQuery)
            else {
                continue
            }

            let title = historyTitle(for: url)
            matches.append(
                AddressHistorySuggestionMatch(
                    rank: rank,
                    offset: offset,
                    suggestion: AddressSuggestion(
                        id: "history-\(url.absoluteString)",
                        title: title,
                        kind: .history(url),
                        faviconURL: faviconURL(for: url)
                    )
                )
            )
        }

        return matches.sorted { lhs, rhs in
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }

            return lhs.offset < rhs.offset
        }
        .map { item in
            item.suggestion
        }
    }

    private static func combinedSuggestions(
        historySuggestions: [AddressSuggestion],
        searchSuggestions: [String]
    ) -> [AddressSuggestion] {
        var seenTitles = Set(historySuggestions.map { $0.title.lowercased() })
        var combinedSuggestions = historySuggestions

        for suggestion in searchSuggestions {
            let normalizedSuggestion = suggestion.lowercased()
            guard !seenTitles.contains(normalizedSuggestion) else { continue }

            seenTitles.insert(normalizedSuggestion)
            combinedSuggestions.append(
                AddressSuggestion(
                    id: "search-\(suggestion)",
                    title: suggestion,
                    kind: .search,
                    faviconURL: nil
                )
            )
        }

        return combinedSuggestions
    }

    private static func historyRank(for url: URL, normalizedQuery: String) -> Int? {
        let displayHost = historyDisplayHost(for: url).lowercased()
        let title = historyTitle(for: url).lowercased()
        let absoluteString = url.absoluteString.lowercased()

        if displayHost.hasPrefix(normalizedQuery) {
            return 0
        }

        if title.hasPrefix(normalizedQuery) {
            return 1
        }

        if displayHost.contains(normalizedQuery) {
            return 2
        }

        if title.contains(normalizedQuery) {
            return 3
        }

        if absoluteString.contains(normalizedQuery) {
            return 4
        }

        return nil
    }

    private static func historyTitle(for url: URL) -> String {
        guard url.host != nil else { return url.absoluteString }

        let displayHost = historyDisplayHost(for: url)
        let path = url.path.isEmpty || url.path == "/" ? "" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        let fragment = url.fragment.map { "#\($0)" } ?? ""

        return "\(displayHost)\(path)\(query)\(fragment)"
    }

    private static func historyDisplayHost(for url: URL) -> String {
        guard let host = url.host else { return url.absoluteString }

        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func faviconURL(for url: URL) -> URL? {
        guard var components = URLComponents(string: "https://www.google.com/s2/favicons") else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "domain_url", value: url.absoluteString),
            URLQueryItem(name: "sz", value: "32")
        ]

        return components.url
    }

    private var browserWorkspace: some View {
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

    private var browserContent: some View {
        ZStack {
            Color(nsColor: browser.viewportMode == .desktop ? .textBackgroundColor : .windowBackgroundColor)

            ZStack {
                BrowserWebView(webView: browser.webView)
                    .opacity(browser.hasAttemptedNavigation ? 1 : 0)

                if !browser.hasAttemptedNavigation {
                    EmptyBrowserState()
                }

                if let errorMessage = browser.errorMessage {
                    BrowserErrorState(message: errorMessage) {
                        browser.reload()
                    }
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

    private var viewportControls: some View {
        HStack(spacing: 2) {
            ForEach(BrowserViewportMode.allCases) { mode in
                Button {
                    browser.setViewportMode(mode)
                } label: {
                    Image(systemName: mode.systemName)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(browser.viewportMode == mode ? Color.accentColor : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(browser.viewportMode == mode ? Color.accentColor.opacity(0.14) : Color.clear)
                )
                .accessibilityLabel(mode.accessibilityLabel)
                .help(mode.helpText)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }

    private var botControls: some View {
        HStack(spacing: 2) {
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
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isBotPanelVisible ? Color.accentColor : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isBotPanelVisible ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .accessibilityLabel("Bot panel")
            .help("Bot panel")
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }

    private var progressBar: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.35))
                .frame(height: 1)

            if browser.isLoading {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: max(24, proxy.size.width * browser.estimatedProgress), height: 2)
                        .animation(.easeOut(duration: 0.18), value: browser.estimatedProgress)
                }
                .frame(height: 2)
                .transition(.opacity)
            }
        }
        .frame(height: 2)
    }
}

private struct BotTerminalPanel: View {
    @ObservedObject var terminal: BotTerminalModel
    @State private var promptText = ""
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        ZStack {
            Color.black

            VStack(spacing: 0) {
                ScrollViewReader { reader in
                    ScrollView {
                        Text(terminal.message)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(red: 0.44, green: 1.0, blue: 0.52))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(16)
                            .id("terminal-end")
                    }
                    .onChange(of: terminal.message) { _, _ in
                        withAnimation(.easeOut(duration: 0.12)) {
                            reader.scrollTo("terminal-end", anchor: .bottom)
                        }
                    }
                }

                if terminal.isInputReady {
                    HStack(spacing: 8) {
                        Text(">")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(red: 0.44, green: 1.0, blue: 0.52))

                        TextField("Ask about this page", text: $promptText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(red: 0.44, green: 1.0, blue: 0.52))
                            .focused($isPromptFocused)
                            .onSubmit {
                                submitPrompt()
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color(red: 0.44, green: 1.0, blue: 0.52).opacity(0.25))
                            .frame(height: 1)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onChange(of: terminal.isInputReady) { _, isReady in
            guard isReady else { return }

            DispatchQueue.main.async {
                isPromptFocused = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(terminal.message)
    }

    private func submitPrompt() {
        let trimmedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        terminal.submitHumanMessage(trimmedPrompt)
        promptText = ""
        isPromptFocused = true
    }
}

private struct BrowserToolbarButton: View {
    let systemName: String
    let accessibilityLabel: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? .tertiary : .primary)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isDisabled ? 0.45 : 1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    ContentView(browser: BrowserModel())
}
