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
        case visit(AddressResolution)
        case history(URL)
        case search(String)
    }

    let id: String
    let title: String
    let kind: Kind
    let faviconURL: URL?

    var accessibilityLabel: String {
        switch kind {
        case .visit:
            "Visit \(title)"
        case .history:
            "Open \(title)"
        case .search(let query):
            "Search \(query)"
        }
    }

    var completionText: String {
        title
    }

    var canInlineComplete: Bool {
        switch kind {
        case .visit, .history:
            true
        case .search:
            false
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
    @State private var addressDraft = ""
    @State private var isAddressFocused = false
    @State private var isBotPanelVisible = false
    @State private var selectedSuggestionIndex: Int?
    @State private var shouldSelectAddressText = false
    @State private var suggestionTask: Task<Void, Never>?
    @State private var suggestions: [AddressSuggestion] = []

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
            focusAddressBar(selectAll: true)
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
        .onChange(of: isAddressFocused) { _, isFocused in
            browser.webView.blocksProgrammaticFocus = isFocused

            if isFocused {
                hideSuggestions()
                scheduleSuggestions(for: addressDraft)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    guard !isAddressFocused else { return }
                    hideSuggestions()
                    addressDraft = browser.displayAddressText
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
                submitAddressField()
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(addressDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

            if !addressDraft.isEmpty {
                Button {
                    addressDraft = ""
                    hideSuggestions()
                    focusAddressBar(selectAll: false, syncToCommittedURL: false)
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

            AddressBarTextField(
                text: $addressDraft,
                isFocused: $isAddressFocused,
                selectAllOnFocus: $shouldSelectAddressText,
                placeholder: "Search or enter a website",
                onSubmit: submitAddressField,
                onCancel: cancelAddressEditing,
                onMoveSelection: moveSuggestionSelection,
                onAcceptCompletion: acceptInlineCompletion,
                shouldPreserveFocus: shouldPreserveAddressFocus
            )
            .frame(height: 20)
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
              suggestion.canInlineComplete
        else {
            return nil
        }

        let typedText = addressDraft
        let trimmedTypedText = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let completionText = suggestion.completionText
        guard !trimmedTypedText.isEmpty,
              typedText == trimmedTypedText,
              completionText.lowercased().hasPrefix(typedText.lowercased()),
              completionText.count > typedText.count
        else {
            return nil
        }

        return AddressCompletion(
            suggestion: suggestion,
            typedText: typedText,
            suffix: String(completionText.dropFirst(typedText.count))
        )
    }

    @ViewBuilder
    private func suggestionIcon(for suggestion: AddressSuggestion) -> some View {
        switch suggestion.kind {
        case .visit:
            Image(systemName: "globe")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
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
        let localSuggestions = Self.localSuggestions(for: query, historyURLs: historyURLs)
        suggestions = localSuggestions

        suggestionTask = Task { [query, historyURLs] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            let fetchedSuggestions = await Self.fetchSuggestions(for: query)
            let localSuggestions = Self.localSuggestions(for: query, historyURLs: historyURLs)
            let combinedSuggestions = Self.combinedSuggestions(
                localSuggestions: localSuggestions,
                searchSuggestions: fetchedSuggestions
            )

            await MainActor.run {
                guard !Task.isCancelled,
                      isAddressFocused,
                      addressDraft.trimmingCharacters(in: .whitespacesAndNewlines) == query
                else {
                    return
                }

                let selectedID = selectedSuggestionIndex.flatMap { index in
                    suggestions.indices.contains(index) ? suggestions[index].id : nil
                }

                suggestions = combinedSuggestions

                if let selectedID,
                   let index = combinedSuggestions.firstIndex(where: { $0.id == selectedID })
                {
                    selectedSuggestionIndex = index
                }
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
        } else {
            hideSuggestions()
            isAddressFocused = false

            if browser.loadAddress(addressDraft) {
                addressDraft = browser.displayAddressText
                focusBrowserContent()
            } else {
                isAddressFocused = true
            }
        }
    }

    private func selectSuggestion(_ suggestion: AddressSuggestion) {
        hideSuggestions()
        isAddressFocused = false

        switch suggestion.kind {
        case .visit(let resolution):
            browser.load(resolution)
        case .history(let url):
            browser.load(url)
        case .search(let query):
            browser.searchGoogle(for: query)
        }

        addressDraft = browser.displayAddressText
        focusBrowserContent()
    }

    private func moveSuggestionSelection(_ delta: Int) -> Bool {
        guard shouldShowSuggestions else { return false }

        if delta > 0 {
            selectNextSuggestion()
        } else {
            selectPreviousSuggestion()
        }

        return true
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

    private func acceptInlineCompletion() -> Bool {
        guard selectedSuggestionIndex == nil,
              let addressCompletion
        else {
            return false
        }

        addressDraft = addressCompletion.suggestion.completionText
        return true
    }

    private func cancelAddressEditing() {
        hideSuggestions()
        addressDraft = browser.displayAddressText
        isAddressFocused = false
        focusBrowserContent()
    }

    private func focusAddressBar(selectAll: Bool, syncToCommittedURL: Bool = true) {
        if syncToCommittedURL {
            addressDraft = browser.displayAddressText
        }

        shouldSelectAddressText = selectAll
        browser.webView.blocksProgrammaticFocus = true
        isAddressFocused = true
    }

    private func shouldPreserveAddressFocus() -> Bool {
        guard isAddressFocused, NSApp.isActive else { return false }

        switch NSApp.currentEvent?.type {
        case .leftMouseDown?, .rightMouseDown?, .otherMouseDown?:
            return false
        default:
            return true
        }
    }

    private func focusBrowserContent() {
        DispatchQueue.main.async {
            browser.webView.focusFromBrowserChrome()
        }
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

    private static func localSuggestions(for query: String, historyURLs: [String]) -> [AddressSuggestion] {
        var suggestions: [AddressSuggestion] = []

        if let resolution = AddressResolver.resolve(query) {
            switch resolution.kind {
            case .webpage:
                let title = resolution.didAppendDotCom ? query : resolution.displayTitle
                suggestions.append(
                    AddressSuggestion(
                        id: "visit-\(resolution.primaryURL.absoluteString)",
                        title: title,
                        kind: .visit(resolution),
                        faviconURL: faviconURL(for: resolution.primaryURL)
                    )
                )
            case .search:
                let searchQuery = resolution.searchQuery ?? query
                suggestions.append(
                    AddressSuggestion(
                        id: "search-current-\(searchQuery)",
                        title: searchQuery,
                        kind: .search(searchQuery),
                        faviconURL: nil
                    )
                )
            }
        }

        let historySuggestions = historySuggestions(for: query, historyURLs: historyURLs)
        return deduplicatedSuggestions(suggestions + historySuggestions)
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
        localSuggestions: [AddressSuggestion],
        searchSuggestions: [String]
    ) -> [AddressSuggestion] {
        var seenTitles = Set(localSuggestions.map { $0.title.lowercased() })
        var combinedSuggestions = localSuggestions

        for suggestion in searchSuggestions {
            let normalizedSuggestion = suggestion.lowercased()
            guard !seenTitles.contains(normalizedSuggestion) else { continue }

            seenTitles.insert(normalizedSuggestion)
            combinedSuggestions.append(
                AddressSuggestion(
                    id: "search-\(suggestion)",
                    title: suggestion,
                    kind: .search(suggestion),
                    faviconURL: nil
                )
            )
        }

        return combinedSuggestions
    }

    private static func deduplicatedSuggestions(_ suggestions: [AddressSuggestion]) -> [AddressSuggestion] {
        var seenTitles = Set<String>()
        var result: [AddressSuggestion] = []

        for suggestion in suggestions {
            let normalizedTitle = suggestion.title.lowercased()
            guard !seenTitles.contains(normalizedTitle) else { continue }

            seenTitles.insert(normalizedTitle)
            result.append(suggestion)
        }

        return result
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
                BrowserWebView(
                    webView: browser.webView,
                    blocksProgrammaticFocus: isAddressFocused
                )
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
