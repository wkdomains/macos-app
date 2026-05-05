//
//  BrowserModel+Tabs.swift
//  macos-app
//

import AppKit
import Combine
import Foundation
import WebKit

struct BrowserTabItem: Identifiable, Equatable {
    var id: UUID
    var title: String
    var url: URL?
    var isActive: Bool
    var isLoading: Bool
    var isPinned: Bool
    var hasAttemptedNavigation: Bool
}

final class BrowserTabState {
    let id: UUID
    var webView: BrowserWKWebView
    let cookiePersistence: BrowserCookiePersistence
    var identityID: UUID?
    var observations: [NSKeyValueObservation] = []
    var isCookieStoreReady = false
    var pendingLoadRequest: (url: URL, fallbackURLs: [URL])?
    var hasAttemptedNavigation = false
    var displayAddressText = ""
    var errorMessage: String?
    var navigationFallbacks: [URL] = []
    var title = BrowserWKWebView.defaultWindowTitle
    var isPinned = false

    init(
        id: UUID = UUID(),
        webView: BrowserWKWebView,
        cookiePersistence: BrowserCookiePersistence,
        identityID: UUID?,
        isPinned: Bool = false
    ) {
        self.id = id
        self.webView = webView
        self.cookiePersistence = cookiePersistence
        self.identityID = identityID
        self.isPinned = isPinned
    }
}

extension BrowserModel {
    var activeTab: BrowserTabState {
        tabStates.first { $0.id == activeTabID } ?? tabStates[0]
    }

    func tab(for webView: WKWebView) -> BrowserTabState? {
        tabStates.first { $0.webView === webView }
    }

    func syncObservedPageState(from webView: WKWebView) {
        guard let tab = tab(for: webView) else { return }

        tab.title = tabTitle(for: webView)

        if let url = webView.url {
            tab.displayAddressText = url.absoluteString
        }

        refreshPublishedTabs()

        guard activeTabID == tab.id else { return }
        syncPageState(from: webView)
    }

    func syncPageState(from webView: WKWebView) {
        guard let tab = tab(for: webView) else { return }

        if let url = webView.url {
            tab.displayAddressText = url.absoluteString
        }

        tab.title = tabTitle(for: webView)
        persistOpenTabs()
        refreshPublishedTabs()

        guard activeTabID == tab.id else { return }

        if let url = webView.url {
            displayAddressText = url.absoluteString
            isSecurePage = url.scheme?.lowercased() == "https"
            refreshDarkModeState(for: url)
        }

        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        estimatedProgress = webView.estimatedProgress
        isLoading = webView.isLoading
        hasAttemptedNavigation = tab.hasAttemptedNavigation
        errorMessage = tab.errorMessage
        refreshSiteIdentityState()
    }

    func syncWindowTitle(from webView: WKWebView) {
        guard let tab = tab(for: webView) else { return }

        tab.title = tabTitle(for: webView)
        refreshPublishedTabs()

        guard activeTabID == tab.id else { return }
        self.webView.browserWindowTitle = BrowserWKWebView.defaultWindowTitle
    }

    func tabTitle(for webView: WKWebView) -> String {
        let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            return title
        }

        return webView.url?.host ?? BrowserWKWebView.defaultWindowTitle
    }

    func selectTab(_ tabID: UUID) {
        guard activeTabID != tabID,
              let tab = tabStates.first(where: { $0.id == tabID })
        else {
            return
        }

        webView.blocksProgrammaticFocus = false
        webView.isActiveBrowserTab = false
        activeTabID = tab.id
        webView = tab.webView
        webView.isActiveBrowserTab = true
        displayAddressText = tab.displayAddressText
        errorMessage = tab.errorMessage
        hasAttemptedNavigation = tab.hasAttemptedNavigation
        isSecurePage = tab.webView.url?.scheme?.lowercased() == "https"
        canGoBack = tab.webView.canGoBack
        canGoForward = tab.webView.canGoForward
        estimatedProgress = tab.webView.estimatedProgress
        isLoading = tab.webView.isLoading
        navigationFallbacks = tab.navigationFallbacks
        resetScreenshotForNavigation()
        resetXHRTracking(for: tab.webView.url)
        refreshSiteIdentityState()
        syncWindowTitle(from: tab.webView)
        refreshPublishedTabs()
        syncTitlebarTabState()
        persistOpenTabs()
    }

    func addEmptyTab() {
        let tab = makeTab(initialURL: nil)
        tabStates.append(tab)
        attachCookiePersistence(to: tab)
        selectTab(tab.id)
    }

    func restoreOpenTabs(_ urls: [URL]) {
        guard !urls.isEmpty else {
            load(settingsStore.startupURL)
            return
        }

        for (tab, url) in zip(tabStates, urls) {
            load(url, in: tab, fallbackURLs: [])
        }
    }

    func closeActiveTab() {
        guard tabStates.count > 1,
              let closingIndex = tabStates.firstIndex(where: { $0.id == activeTabID })
        else {
            return
        }

        let closingTab = tabStates[closingIndex]
        let nextIndex = closingIndex == tabStates.index(before: tabStates.endIndex)
            ? tabStates.index(before: closingIndex)
            : tabStates.index(after: closingIndex)
        let nextTabID = tabStates[nextIndex].id

        closingTab.webView.stopLoading()
        closingTab.cookiePersistence.saveNow()
        detach(closingTab.webView)
        closingTab.observations.removeAll()
        tabStates.remove(at: closingIndex)
        selectTab(nextTabID)
        persistOpenTabs()
    }

    func moveTab(_ sourceID: UUID, to targetID: UUID) {
        guard let sourceIndex = tabStates.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = tabStates.firstIndex(where: { $0.id == targetID }),
              sourceIndex != targetIndex,
              tabStates[sourceIndex].isPinned == tabStates[targetIndex].isPinned
        else {
            return
        }

        let movedTab = tabStates.remove(at: sourceIndex)
        tabStates.insert(movedTab, at: targetIndex)
        refreshPublishedTabs()
        persistOpenTabs()
    }

    func moveTab(_ sourceID: UUID, toDropIndex rawDropIndex: Int) {
        guard let sourceIndex = tabStates.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        let isPinned = tabStates[sourceIndex].isPinned
        let groupStart = isPinned ? 0 : (tabStates.firstIndex { !$0.isPinned } ?? tabStates.endIndex)
        let groupEnd = isPinned
            ? (tabStates.firstIndex { !$0.isPinned } ?? tabStates.endIndex)
            : tabStates.endIndex
        let dropIndex = min(max(rawDropIndex, groupStart), groupEnd)
        let insertionIndex = sourceIndex < dropIndex ? dropIndex - 1 : dropIndex

        guard insertionIndex != sourceIndex else {
            return
        }

        let movedTab = tabStates.remove(at: sourceIndex)
        tabStates.insert(movedTab, at: insertionIndex)
        refreshPublishedTabs()
        persistOpenTabs()
    }

    func togglePinnedTab(_ tabID: UUID) {
        guard let tab = tabStates.first(where: { $0.id == tabID }) else { return }
        setTab(tabID, pinned: !tab.isPinned)
    }

    func setTab(_ tabID: UUID, pinned: Bool) {
        guard let sourceIndex = tabStates.firstIndex(where: { $0.id == tabID }),
              tabStates[sourceIndex].isPinned != pinned
        else {
            return
        }

        let tab = tabStates.remove(at: sourceIndex)
        tab.isPinned = pinned

        let targetIndex = tabStates.firstIndex { !$0.isPinned } ?? tabStates.endIndex
        tabStates.insert(tab, at: targetIndex)

        refreshPublishedTabs()
        persistOpenTabs()
    }

    func makeTab(initialURL: URL?) -> BrowserTabState {
        let identityID = initialURL.flatMap { settingsStore.activeIdentityID(for: $0) }
        let webView = Self.makeWebView(
            dataStore: Self.websiteDataStore(for: identityID),
            usesDarkMode: settingsStore.usesDarkMode(for: initialURL)
        )
        let tab = BrowserTabState(
            webView: webView,
            cookiePersistence: BrowserCookiePersistence(directoryURL: settingsStore.directoryURL),
            identityID: identityID
        )
        configure(tab)
        return tab
    }

    func refreshPublishedTabs() {
        tabs = tabStates.map { tab in
            BrowserTabItem(
                id: tab.id,
                title: tab.title,
                url: tab.webView.url,
                isActive: tab.id == activeTabID,
                isLoading: tab.webView.isLoading,
                isPinned: tab.isPinned,
                hasAttemptedNavigation: tab.hasAttemptedNavigation
            )
        }

        syncTitlebarTabState()
    }

    func persistOpenTabs() {
        var openTabURLs: [String] = []
        var openTabPins: [Bool] = []
        var persistedActiveIndex = 0

        for tab in tabStates {
            let urlString = tab.webView.url?.absoluteString
                ?? (tab.hasAttemptedNavigation ? tab.displayAddressText : nil)
            guard let urlString, !urlString.isEmpty else { continue }

            if tab.id == activeTabID {
                persistedActiveIndex = openTabURLs.count
            }
            openTabURLs.append(urlString)
            openTabPins.append(tab.isPinned)
        }

        settingsStore.updateOpenTabs(openTabURLs, activeIndex: persistedActiveIndex, pinnedFlags: openTabPins)
    }

    func syncTitlebarTabState() {
        let items = tabStates.map { tab in
            BrowserTitlebarTab(
                id: tab.id,
                title: tab.title,
                url: tab.webView.url,
                isActive: tab.id == activeTabID,
                isLoading: tab.webView.isLoading,
                isPinned: tab.isPinned,
                hasAttemptedNavigation: tab.hasAttemptedNavigation
            )
        }

        activeTab.webView.titlebarTabs = items
    }

}
