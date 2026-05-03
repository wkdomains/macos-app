//
//  BrowserModel.swift
//  macos-app
//
//  Created by aa on 5/2/26.
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
    var hasAttemptedNavigation: Bool
}

private final class BrowserTabState {
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

    init(
        id: UUID = UUID(),
        webView: BrowserWKWebView,
        cookiePersistence: BrowserCookiePersistence,
        identityID: UUID?
    ) {
        self.id = id
        self.webView = webView
        self.cookiePersistence = cookiePersistence
        self.identityID = identityID
    }
}

final class BrowserModel: NSObject, ObservableObject {
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var displayAddressText = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var estimatedProgress = 0.0
    @Published private(set) var hasAttemptedNavigation = false
    @Published private(set) var historyURLs: [String]
    @Published private(set) var bookmarkURLs: [URL]
    @Published private(set) var tabs: [BrowserTabItem] = []
    @Published private(set) var activeTabID: UUID
    @Published private(set) var isLoading = false
    @Published private(set) var isSecurePage = false
    @Published private(set) var currentIdentityName = "Default"
    @Published private(set) var siteIdentityMenuItems: [BrowserSiteIdentityMenuItem] = [
        BrowserSiteIdentityMenuItem(id: BrowserSiteIdentityMenuItem.defaultID, title: "Default", isCurrent: true)
    ]
    @Published private(set) var viewportMode: BrowserViewportMode = .desktop
    @Published private(set) var webViewID = UUID()

    @Published private(set) var webView: BrowserWKWebView
    let botTerminal = BotTerminalModel()

    private var tabStates: [BrowserTabState]
    private let loginStore: LoginStore
    let settingsStore: AppSettingsStore
    private var activePageHost: String?
    private var pendingLoginUsernameTarget: LoginFieldTarget?
    private var pendingLoginPasswordTarget: LoginFieldTarget?
    private var consoleRecords: [ConsoleMessageRecord] = []
    private var xhrRecords: [XHRRequestRecord] = []
    private var xhrRecordIndexesByID: [String: Int] = [:]
    var screenshotPNG: Data?
    var screenshotCapturedVersion = -1
    var screenshotDirtyVersion = 0
    var screenshotNavigationGeneration = 0
    var screenshotIsRendering = false
    var screenshotRenderTask: Task<Void, Never>?
    var screenshotWaiters: [UUID: (Result<Data, Error>) -> Void] = [:]
    private var navigationFallbacks: [URL] = []

    init(
        dataStore: WKWebsiteDataStore? = nil,
        activeIdentityID: UUID? = nil,
        settingsStore: AppSettingsStore = .shared
    ) {
        self.settingsStore = settingsStore
        loginStore = LoginStore(directoryURL: settingsStore.directoryURL)
        historyURLs = settingsStore.settings.historyURLs
        bookmarkURLs = settingsStore.bookmarkURLs
        let initialIdentityID = activeIdentityID ?? settingsStore.activeIdentityID(for: settingsStore.startupURL)

        let initialDataStore = dataStore ?? Self.websiteDataStore(for: initialIdentityID)
        let initialWebView = Self.makeWebView(
            dataStore: initialDataStore,
            usesDarkMode: settingsStore.usesDarkMode(for: settingsStore.startupURL)
        )
        let initialTab = BrowserTabState(
            webView: initialWebView,
            cookiePersistence: BrowserCookiePersistence(directoryURL: settingsStore.directoryURL),
            identityID: initialIdentityID
        )
        tabStates = [initialTab]
        activeTabID = initialTab.id
        webView = initialWebView

        super.init()

        configure(initialTab)
        refreshSiteIdentityState()
        refreshPublishedTabs()
        attachCookiePersistence(to: initialTab)
    }

    private static func websiteDataStore(for identityID: UUID?) -> WKWebsiteDataStore {
        guard let identityID else {
            return .default()
        }

        return WKWebsiteDataStore(forIdentifier: identityID)
    }

    private static func makeWebView(dataStore: WKWebsiteDataStore, usesDarkMode: Bool) -> BrowserWKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.applicationNameForUserAgent = safariApplicationNameForUserAgent

        let webView = BrowserWKWebView(frame: .zero, configuration: configuration)
        webView.configureForcedDarkPageBackground(usesDarkMode)
        return webView
    }

    private static var safariApplicationNameForUserAgent: String {
        "Version/\(installedSafariVersion ?? "18.0") Safari/605.1.15"
    }

    private static var installedSafariVersion: String? {
        let appURLs = [
            URL(fileURLWithPath: "/Applications/Safari.app"),
            URL(fileURLWithPath: "/System/Applications/Safari.app")
        ]

        for appURL in appURLs {
            guard let bundle = Bundle(url: appURL),
                  let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            else {
                continue
            }

            let components = version.split(separator: ".").prefix(2)
            let normalizedVersion = components.joined(separator: ".")
            if !normalizedVersion.isEmpty {
                return normalizedVersion
            }
        }

        return nil
    }

    private var activeTab: BrowserTabState {
        tabStates.first { $0.id == activeTabID } ?? tabStates[0]
    }

    private func tab(for webView: WKWebView) -> BrowserTabState? {
        tabStates.first { $0.webView === webView }
    }

    private func configure(_ tab: BrowserTabState) {
        let webView = tab.webView
        webView.allowsBackForwardNavigationGestures = true
        webView.browserContextMenuDelegate = self
        webView.selectTab = { [weak self] tabID in
            self?.selectTab(tabID)
        }
        webView.addTab = { [weak self] in
            self?.addEmptyTab()
        }
        syncTitlebarTabState()
        webView.viewportSizeDidChange = { [weak self] in
            guard self?.webView === webView else { return }
            self?.markScreenshotDirty(scheduleAfter: 0.25)
        }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        installPageTrackingScripts(on: webView.configuration.userContentController)

        tab.observations = [
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.syncObservedPageState(from: webView)
                }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.syncObservedPageState(from: webView)
                }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.syncObservedPageState(from: webView)
                }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.syncObservedPageState(from: webView)
                }
            },
            webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.syncPageState(from: webView)
                }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.syncWindowTitle(from: webView)
                }
            }
        ]
    }

    @discardableResult
    func loadAddress(_ rawValue: String) -> Bool {
        guard let resolution = AddressResolver.resolve(rawValue) else {
            errorMessage = "Enter a valid http or https address."
            return false
        }

        load(resolution)
        return true
    }

    func searchWeb(for query: String) {
        guard let url = AddressResolver.searchURL(for: query) else { return }
        load(url)
    }

    func goBack() {
        guard webView.canGoBack else { return }
        activeTab.errorMessage = nil
        activeTab.navigationFallbacks = []
        errorMessage = nil
        navigationFallbacks = []
        webView.goBack()
    }

    func goForward() {
        guard webView.canGoForward else { return }
        activeTab.errorMessage = nil
        activeTab.navigationFallbacks = []
        errorMessage = nil
        navigationFallbacks = []
        webView.goForward()
    }

    func reload() {
        guard hasAttemptedNavigation else { return }
        activeTab.errorMessage = nil
        activeTab.navigationFallbacks = []
        errorMessage = nil

        navigationFallbacks = []

        if webView.url == nil {
            loadAddress(displayAddressText)
        } else {
            webView.reload()
        }
    }

    func stopLoading() {
        webView.stopLoading()
        isLoading = false
    }

    func saveCookiesNow() {
        activeTab.cookiePersistence.saveNow()
    }

    func clearCookiesForCurrentDomain() {
        guard let host = webView.url?.host?.lowercased() else { return }
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore

        cookieStore.getAllCookies { cookies in
            let matchingCookies = cookies.filter { cookie in
                let cookieDomain = cookie.domain
                    .lowercased()
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))

                return cookieDomain == host
                    || cookieDomain.hasSuffix(".\(host)")
                    || host.hasSuffix(".\(cookieDomain)")
            }

            for cookie in matchingCookies {
                cookieStore.delete(cookie)
            }
        }
    }

    func createFreshSiteIdentityForCurrentSite() {
        guard let currentURL = webView.url,
              let identity = settingsStore.createIdentity(for: currentURL)
        else {
            return
        }

        activeTab.identityID = identity.id
        replaceWebView(using: identity.id, loading: Self.siteBaseURL(for: currentURL))
        refreshSiteIdentityState()
    }

    func switchToSiteIdentity(_ menuItemID: String) {
        guard let currentURL = webView.url else { return }

        let nextIdentityID: UUID?
        if menuItemID == BrowserSiteIdentityMenuItem.defaultID {
            nextIdentityID = nil
        } else {
            guard let identityID = UUID(uuidString: menuItemID) else { return }
            nextIdentityID = identityID
        }

        guard nextIdentityID != activeTab.identityID else { return }

        settingsStore.setActiveIdentity(nextIdentityID, for: currentURL)
        activeTab.identityID = nextIdentityID
        replaceWebView(using: nextIdentityID, loading: Self.siteBaseURL(for: currentURL))
        refreshSiteIdentityState()
    }

    var canFillSavedLoginForCurrentSite: Bool {
        loginStore.hasLogin(for: webView.url, identityID: activeTab.identityID)
    }

    func useLoginFieldFromContextMenu(_ role: LoginFieldRole, target: LoginFieldTarget) {
        switch role {
        case .username:
            pendingLoginUsernameTarget = target
        case .password:
            pendingLoginPasswordTarget = target
        }

        guard let usernameTarget = pendingLoginUsernameTarget,
              let passwordTarget = pendingLoginPasswordTarget
        else {
            return
        }

        armLoginCapture(usernameTarget: usernameTarget, passwordTarget: passwordTarget)
    }

    func fillSavedLoginForCurrentSite() {
        fillSavedLoginForCurrentSite(reportsMissingLogin: true)
    }

    var canToggleDarkThemeForCurrentSite: Bool {
        settingsStore.isGlobalDarkModeEnabled && webView.url?.host != nil
    }

    var currentSiteIsExcludedFromDarkTheme: Bool {
        settingsStore.isDarkModeDisabled(for: webView.url)
    }

    func toggleDarkThemeForCurrentSite() {
        guard settingsStore.isGlobalDarkModeEnabled,
              let currentURL = webView.url
        else {
            return
        }

        settingsStore.toggleDarkModeDisabled(for: currentURL)
        refreshDarkModeState(for: currentURL)
        reinstallPageTrackingUserScripts()
        webView.reload()
    }

    var canBookmarkCurrentPage: Bool {
        guard webView.url?.host != nil,
              let scheme = webView.url?.scheme?.lowercased()
        else {
            return false
        }

        return ["http", "https"].contains(scheme)
    }

    var currentPageIsBookmarked: Bool {
        settingsStore.isBookmarked(webView.url)
    }

    func toggleBookmarkForCurrentPage() {
        guard let currentURL = webView.url else { return }
        settingsStore.toggleBookmark(for: currentURL)
        syncBookmarkState()
    }

    func moveBookmark(_ sourceURL: URL, to targetURL: URL) {
        settingsStore.moveBookmark(sourceURL, to: targetURL)
        syncBookmarkState()
    }

    func xhrRequests(for host: String) -> [XHRRequestRecord] {
        let normalizedHost = Self.normalizedHost(host)

        return xhrRecords.filter { record in
            guard let recordHost = record.host ?? URL(string: record.url)?.host else {
                return false
            }

            return Self.host(recordHost, matches: normalizedHost)
        }
    }

    func sortedXHRRequests(for host: String) -> [XHRRequestRecord] {
        xhrRequests(for: host).sorted { left, right in
            let leftBytes = Self.xhrResponseByteSortKey(left)
            let rightBytes = Self.xhrResponseByteSortKey(right)

            if leftBytes == rightBytes {
                return left.startedAt < right.startedAt
            }

            return leftBytes > rightBytes
        }
    }

    var xhrContextMenuItems: [XHRContextMenuItem] {
        guard let host = webView.url?.host else {
            return []
        }

        return sortedXHRRequests(for: host)
            .prefix(9)
            .enumerated()
            .map { offset, record in
                XHRContextMenuItem(index: offset, title: Self.xhrMenuTitle(for: record, at: offset))
            }
    }

    func openXHRFromContextMenu(at index: Int) {
        guard let host = webView.url?.host else {
            showAlert(message: "No Page Loaded", detail: InspectionError.noPageLoaded.localizedDescription)
            return
        }

        let requests = sortedXHRRequests(for: host)
        guard requests.indices.contains(index) else {
            showAlert(message: "XHR Not Available", detail: InspectionError.xhrIndexOutOfRange(index).localizedDescription)
            return
        }

        let record = requests[index]
        guard let url = URL(string: record.url) else {
            showAlert(message: "XHR Not Available", detail: InspectionError.invalidXHRURL.localizedDescription)
            return
        }

        let xhr = XHRRequestResponse(record: record)
        let dataStore = webView.configuration.websiteDataStore
        dataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let cookieHeader = WebsiteDataReader.cookieHeader(for: url, from: cookies)

                do {
                    let response = try await WebsiteDataReader.fetchXHRJSON(
                        xhr: xhr,
                        url: url,
                        cookieHeader: cookieHeader
                    )
                    self.displayXHRJSON(response, from: url)
                } catch {
                    self.showAlert(message: "Could Not Open XHR", detail: error.localizedDescription)
                }
            }
        }
    }

    func consoleMessages() -> [ConsoleMessageRecord] {
        consoleRecords
    }

    func setViewportMode(_ mode: BrowserViewportMode) {
        guard viewportMode != mode else { return }
        viewportMode = mode
        markScreenshotDirty(scheduleAfter: 0.35)
    }

    func requestLLMSSummary() {
        botTerminal.open(
            currentURL: webView.url,
            pageTitle: webView.title,
            viewportMode: viewportMode,
            xhrCount: xhrRecords.count
        )
    }

    func closeBotTerminal() {
        botTerminal.close()
    }

    func setLocalAPIBaseURL(_ baseURL: String) {
        botTerminal.setLocalAPIBaseURL(baseURL)
    }

    func pendingBotRequests() -> [BotTerminalRequest] {
        botTerminal.pendingRequests()
    }

    func waitForPendingBotRequests(timeout: TimeInterval, completion: @escaping (_ requests: [BotTerminalRequest], _ timedOut: Bool) -> Void) {
        botTerminal.waitForPendingRequests(timeout: timeout, completion: completion)
    }

    func replyToBotRequest(id: UUID, summary: String) -> Bool {
        botTerminal.completeRequest(id: id, summary: summary)
    }

    func updateBotRequest(id: UUID, status: String) -> Bool {
        botTerminal.updateRequest(id: id, status: status)
    }

    func load(_ url: URL) {
        load(url, fallbackURLs: [])
    }

    func load(_ resolution: AddressResolution) {
        load(resolution.primaryURL, fallbackURLs: resolution.fallbackURLs)
    }

    private func load(_ url: URL, fallbackURLs: [URL]) {
        prepareForLoad(url, fallbackURLs: fallbackURLs)

        let tab = activeTab
        guard tab.isCookieStoreReady else {
            tab.pendingLoadRequest = (url, fallbackURLs)
            return
        }

        webView.load(URLRequest(url: url))
    }

    private func prepareForLoad(_ url: URL, fallbackURLs: [URL]) {
        let tab = activeTab
        tab.hasAttemptedNavigation = true
        tab.errorMessage = nil
        tab.displayAddressText = url.absoluteString
        tab.navigationFallbacks = fallbackURLs

        hasAttemptedNavigation = true
        errorMessage = nil
        displayAddressText = url.absoluteString
        isSecurePage = url.scheme?.lowercased() == "https"
        navigationFallbacks = fallbackURLs
        resetXHRTracking(for: url)
        refreshDarkModeState(for: url)
        refreshPublishedTabs()
    }

    private func replaceWebView(using identityID: UUID?, loading url: URL) {
        let tab = activeTab
        let oldWebView = tab.webView
        oldWebView.stopLoading()
        detach(oldWebView)
        tab.observations.removeAll()
        tab.pendingLoadRequest = nil
        tab.isCookieStoreReady = false
        tab.identityID = identityID
        tab.hasAttemptedNavigation = true
        tab.displayAddressText = url.absoluteString
        tab.errorMessage = nil
        tab.navigationFallbacks = []
        tab.title = BrowserWKWebView.defaultWindowTitle

        resetScreenshotForNavigation()
        resetXHRTracking(for: url)
        errorMessage = nil
        navigationFallbacks = []
        displayAddressText = url.absoluteString
        isSecurePage = url.scheme?.lowercased() == "https"
        canGoBack = false
        canGoForward = false
        estimatedProgress = 0
        isLoading = false
        hasAttemptedNavigation = true

        let nextWebView = Self.makeWebView(
            dataStore: Self.websiteDataStore(for: identityID),
            usesDarkMode: settingsStore.usesDarkMode(for: url)
        )
        tab.webView = nextWebView
        configure(tab)
        webView = nextWebView
        webViewID = UUID()
        refreshPublishedTabs()
        syncTitlebarTabState()
        attachCookiePersistence(to: tab) { [weak self, weak nextWebView] in
            guard let self,
                  let nextWebView,
                  self.webView === nextWebView
            else {
                return
            }

            nextWebView.load(URLRequest(url: url))
        }
    }

    private func attachCookiePersistence(
        to tab: BrowserTabState,
        afterRestore: (() -> Void)? = nil
    ) {
        let webView = tab.webView
        tab.cookiePersistence.attach(to: webView.configuration.websiteDataStore, identityID: tab.identityID) { [weak self, weak webView] in
            DispatchQueue.main.async {
                guard let self,
                      let webView,
                      tab.webView === webView
                else {
                    return
                }

                tab.isCookieStoreReady = true

                if let afterRestore {
                    afterRestore()
                    return
                }

                guard let pendingLoadRequest = tab.pendingLoadRequest else { return }
                tab.pendingLoadRequest = nil

                if self.activeTabID == tab.id {
                    self.load(pendingLoadRequest.url, fallbackURLs: pendingLoadRequest.fallbackURLs)
                } else {
                    webView.load(URLRequest(url: pendingLoadRequest.url))
                }
            }
        }
    }

    private func detach(_ webView: BrowserWKWebView) {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.browserContextMenuDelegate = nil
        webView.selectTab = nil
        webView.addTab = nil
        webView.viewportSizeDidChange = nil
        webView.removeTitlebarTabsAccessory()

        let userContentController = webView.configuration.userContentController
        userContentController.removeScriptMessageHandler(forName: "wkdomainsXHR")
        userContentController.removeScriptMessageHandler(forName: "wkdomainsRender")
        userContentController.removeScriptMessageHandler(forName: "wkdomainsConsole")
        userContentController.removeScriptMessageHandler(forName: "wkdomainsLogin")
    }

    private func resetXHRTracking(for url: URL?) {
        activePageHost = url?.host?.lowercased()
        xhrRecords.removeAll(keepingCapacity: true)
        xhrRecordIndexesByID.removeAll(keepingCapacity: true)
        consoleRecords.removeAll(keepingCapacity: true)
    }

    private func recordConsoleMessage(_ message: [String: Any]) {
        let rawArguments = message["arguments"] as? [Any] ?? []
        let arguments = rawArguments.map { value in
            if let value = value as? String {
                return value
            }

            return String(describing: value)
        }

        let record = ConsoleMessageRecord(
            id: UUID(),
            level: message["level"] as? String ?? "log",
            message: message["message"] as? String ?? arguments.joined(separator: " "),
            arguments: arguments,
            pageURL: message["pageURL"] as? String,
            pageHost: (message["pageHost"] as? String)?.lowercased(),
            stack: message["stack"] as? String,
            createdAt: Date()
        )

        consoleRecords.append(record)
        if consoleRecords.count > 200 {
            consoleRecords.removeFirst(consoleRecords.count - 200)
        }
    }

    private func recordXHRMessage(_ message: [String: Any]) {
        guard let event = message["event"] as? String,
              let id = message["id"] as? String
        else {
            return
        }

        if event == "start" {
            guard let rawURL = message["url"] as? String,
                  let url = URL(string: rawURL)
            else {
                return
            }

            let record = XHRRequestRecord(
                id: id,
                kind: message["kind"] as? String ?? "xhr",
                method: (message["method"] as? String ?? "GET").uppercased(),
                url: url.absoluteString,
                host: url.host?.lowercased(),
                pageURL: message["pageURL"] as? String,
                pageHost: (message["pageHost"] as? String)?.lowercased(),
                requestHeaders: Self.stringDictionary(from: message["requestHeaders"]),
                userAgent: message["userAgent"] as? String,
                startedAt: Date(),
                completedAt: nil,
                status: nil,
                responseURL: nil,
                responseBytes: nil,
                jsonType: nil,
                jsonItems: nil,
                jsonShape: nil,
                error: nil
            )

            xhrRecordIndexesByID[id] = xhrRecords.count
            xhrRecords.append(record)
            return
        }

        guard let index = xhrRecordIndexesByID[id],
              xhrRecords.indices.contains(index)
        else {
            return
        }

        xhrRecords[index].completedAt = Date()
        xhrRecords[index].status = Self.intValue(from: message["status"])
        xhrRecords[index].responseURL = message["responseURL"] as? String
        xhrRecords[index].responseBytes = Self.intValue(from: message["responseBytes"])
        xhrRecords[index].jsonType = message["jsonType"] as? String
        xhrRecords[index].jsonItems = Self.intValue(from: message["jsonItems"])
        xhrRecords[index].jsonShape = message["jsonShape"] as? String
        xhrRecords[index].error = message["error"] as? String

        markScreenshotDirty(scheduleAfter: 0.45)
    }

    private func syncObservedPageState(from webView: WKWebView) {
        guard let tab = tab(for: webView) else { return }

        tab.title = tabTitle(for: webView)

        if let url = webView.url {
            tab.displayAddressText = url.absoluteString
        }

        refreshPublishedTabs()

        guard activeTabID == tab.id else { return }
        syncPageState(from: webView)
    }

    private func syncPageState(from webView: WKWebView) {
        guard let tab = tab(for: webView) else { return }

        if let url = webView.url {
            tab.displayAddressText = url.absoluteString
        }

        tab.title = tabTitle(for: webView)
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

    private func syncWindowTitle(from webView: WKWebView) {
        guard let tab = tab(for: webView) else { return }

        tab.title = tabTitle(for: webView)
        refreshPublishedTabs()

        guard activeTabID == tab.id else { return }

        if tab.title != BrowserWKWebView.defaultWindowTitle {
            self.webView.browserWindowTitle = tab.title
        } else {
            self.webView.browserWindowTitle = BrowserWKWebView.defaultWindowTitle
        }
    }

    private func tabTitle(for webView: WKWebView) -> String {
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
        activeTabID = tab.id
        webView = tab.webView
        webViewID = UUID()
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
    }

    func addEmptyTab() {
        let tab = makeTab(initialURL: nil)
        tabStates.append(tab)
        attachCookiePersistence(to: tab)
        selectTab(tab.id)
    }

    private func makeTab(initialURL: URL?) -> BrowserTabState {
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

    private func refreshPublishedTabs() {
        tabs = tabStates.map { tab in
            BrowserTabItem(
                id: tab.id,
                title: tab.title,
                url: tab.webView.url,
                isActive: tab.id == activeTabID,
                isLoading: tab.webView.isLoading,
                hasAttemptedNavigation: tab.hasAttemptedNavigation
            )
        }

        syncTitlebarTabState()
    }

    private func syncTitlebarTabState() {
        let items = tabStates.map { tab in
            BrowserTitlebarTab(
                id: tab.id,
                title: tab.title,
                url: tab.webView.url,
                isActive: tab.id == activeTabID,
                isLoading: tab.webView.isLoading,
                hasAttemptedNavigation: tab.hasAttemptedNavigation
            )
        }

        for tab in tabStates {
            tab.webView.titlebarTabs = items
        }
    }

    private func recordVisitedURL(_ url: URL, identityID: UUID?) {
        settingsStore.updateLastVisitedURL(url, identityID: identityID)
        historyURLs = settingsStore.settings.historyURLs
        refreshSiteIdentityState()
    }

    private func armLoginCapture(
        usernameTarget: LoginFieldTarget,
        passwordTarget: LoginFieldTarget
    ) {
        guard let data = try? JSONEncoder().encode([
            "usernameTarget": usernameTarget,
            "passwordTarget": passwordTarget
        ]),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }

        webView.evaluateJavaScript(Self.loginCaptureScript(targetsJSON: json))
    }

    private func saveCapturedLogin(_ message: [String: Any]) {
        guard let currentURL = (message["pageURL"] as? String).flatMap(URL.init(string:)) ?? webView.url,
              let usernameTarget = pendingLoginUsernameTarget,
              let passwordTarget = pendingLoginPasswordTarget,
              let username = message["username"] as? String,
              let password = message["password"] as? String,
              !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.isEmpty
        else {
            return
        }

        loginStore.save(
            username: username,
            password: password,
            usernameTarget: usernameTarget,
            passwordTarget: passwordTarget,
            for: currentURL,
            identityID: activeTab.identityID
        )
        pendingLoginUsernameTarget = nil
        pendingLoginPasswordTarget = nil
    }

    private func fillSavedLoginForCurrentSite(reportsMissingLogin: Bool) {
        guard let entry = loginStore.login(for: webView.url, identityID: activeTab.identityID) else {
            if reportsMissingLogin {
                showAlert(message: "No Saved Login", detail: "There is no saved login for this site yet.")
            }
            return
        }

        guard let data = try? JSONEncoder().encode(entry),
              let json = String(data: data, encoding: .utf8)
        else {
            if reportsMissingLogin {
                showAlert(message: "Could Not Fill Login", detail: "The saved login could not be encoded.")
            }
            return
        }

        let script = Self.loginFillScript(entryJSON: json)
        webView.evaluateJavaScript(script) { [weak self] value, error in
            DispatchQueue.main.async {
                if reportsMissingLogin,
                   let error
                {
                    self?.showAlert(message: "Could Not Fill Login", detail: error.localizedDescription)
                    return
                }

                if reportsMissingLogin,
                   let filled = Self.intValue(from: value),
                   filled == 0
                {
                    self?.showAlert(
                        message: "Could Not Find Login Fields",
                        detail: "The saved fields were not found on this page."
                    )
                }
            }
        }
    }

    private func displayXHRJSON(_ response: XHRReplayResponse, from url: URL) {
        let mimeType = response.contentType?
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init) ?? "application/json"

        webView.load(
            response.body,
            mimeType: mimeType,
            characterEncodingName: "utf-8",
            baseURL: url
        )
    }

    private func showAlert(message: String, detail: String) {
        guard let window = webView.window else { return }

        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    private func refreshSiteIdentityState() {
        currentIdentityName = settingsStore.identityName(for: activeTab.identityID)
        siteIdentityMenuItems = settingsStore.siteIdentityMenuItems(
            for: webView.url,
            activeIdentityID: activeTab.identityID
        )
    }

    private func syncBookmarkState() {
        bookmarkURLs = settingsStore.bookmarkURLs
    }

    private func refreshDarkModeState(for url: URL?) {
        webView.configureForcedDarkPageBackground(settingsStore.usesDarkMode(for: url))
    }

    private static func xhrResponseByteSortKey(_ record: XHRRequestRecord) -> Int {
        record.responseBytes ?? -1
    }

    private static let xhrMenuByteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        return formatter
    }()

    private static func xhrMenuTitle(for record: XHRRequestRecord, at index: Int) -> String {
        var title = "\(index + 1) \(record.method) \(xhrMenuURLTitle(record.url))"
        var details: [String] = []

        if let status = record.status {
            details.append(String(status))
        }

        if let responseBytes = record.responseBytes {
            details.append(xhrMenuByteFormatter.string(fromByteCount: Int64(responseBytes)))
        }

        if !details.isEmpty {
            title += " [\(details.joined(separator: ", "))]"
        }

        guard title.count > 90 else { return title }
        return "\(title.prefix(87))..."
    }

    private static func xhrMenuURLTitle(_ rawURL: String) -> String {
        guard let url = URL(string: rawURL),
              let host = url.host
        else {
            return rawURL
        }

        let displayHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query.map { "?\($0)" } ?? ""

        return "\(displayHost)\(path)\(query)"
    }

    private static func normalizedHost(_ host: String) -> String {
        host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func siteBaseURL(for url: URL) -> URL {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host?.lowercased()
        else {
            return url
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host

        return components.url ?? url
    }

    private static func host(_ host: String, matches requestedHost: String) -> Bool {
        let host = normalizedHost(host)

        return host == requestedHost
            || host.hasSuffix(".\(requestedHost)")
            || requestedHost.hasSuffix(".\(host)")
    }

    private static func intValue(from value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return nil
    }

    private static func stringDictionary(from value: Any?) -> [String: String] {
        guard let dictionary = value as? [String: Any] else {
            return [:]
        }

        var result: [String: String] = [:]
        for (key, value) in dictionary {
            guard let string = value as? String else {
                continue
            }

            result[key.lowercased()] = string
        }

        return result
    }


}


extension BrowserModel: BrowserContextMenuDelegate {}

extension BrowserModel: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else {
            return
        }

        switch message.name {
        case "wkdomainsXHR":
            recordXHRMessage(body)
        case "wkdomainsRender":
            markScreenshotDirty(scheduleAfter: 0.35)
        case "wkdomainsConsole":
            recordConsoleMessage(body)
        case "wkdomainsLogin":
            saveCapturedLogin(body)
        default:
            return
        }
    }
}

extension BrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard let tab = tab(for: webView) else { return }

        tab.errorMessage = nil
        tab.hasAttemptedNavigation = true

        if activeTabID == tab.id {
            errorMessage = nil
            hasAttemptedNavigation = true
            isLoading = true
            estimatedProgress = max(0.08, webView.estimatedProgress)
            resetScreenshotForNavigation()
            resetXHRTracking(for: webView.url)
        }

        syncPageState(from: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let tab = tab(for: webView) else { return }

        tab.errorMessage = nil
        tab.navigationFallbacks = []

        if activeTabID == tab.id {
            errorMessage = nil
            navigationFallbacks = []
        }

        syncPageState(from: webView)

        if let url = webView.url {
            recordVisitedURL(url, identityID: tab.identityID)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let tab = tab(for: webView) else { return }

        tab.errorMessage = nil

        if activeTabID == tab.id {
            errorMessage = nil
            estimatedProgress = 1
        }

        syncPageState(from: webView)

        if activeTabID == tab.id {
            markScreenshotDirty(scheduleAfter: 0.25)
            botTerminal.refreshIfOpen(
                currentURL: webView.url,
                pageTitle: webView.title,
                viewportMode: viewportMode,
                xhrCount: xhrRecords.count
            )
        }

        if let url = webView.url {
            recordVisitedURL(url, identityID: tab.identityID)
        }

        if activeTabID == tab.id {
            fillSavedLoginForCurrentSite(reportsMissingLogin: false)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error, in: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if loadNextFallback(after: error, in: webView) {
            return
        }

        handleNavigationError(error, in: webView)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if let scheme = url.scheme?.lowercased(), !["http", "https", "about"].contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        if let browserWebView = webView as? BrowserWKWebView {
            browserWebView.configureForcedDarkPageBackground(settingsStore.usesDarkMode(for: url))
        }
        decisionHandler(.allow)
    }

    private func handleNavigationError(_ error: Error, in webView: WKWebView) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }

        guard let tab = tab(for: webView) else { return }
        tab.navigationFallbacks = []
        tab.errorMessage = error.localizedDescription

        if activeTabID == tab.id {
            navigationFallbacks = []
            isLoading = false
            estimatedProgress = 0
            errorMessage = error.localizedDescription
            finishScreenshotWaiters(with: .failure(error))
        }

        refreshPublishedTabs()
    }

    private func loadNextFallback(after error: Error, in webView: WKWebView) -> Bool {
        let nsError = error as NSError
        guard let tab = tab(for: webView) else { return false }
        guard nsError.code != NSURLErrorCancelled,
              !tab.navigationFallbacks.isEmpty
        else {
            return false
        }

        let nextURL = tab.navigationFallbacks.removeFirst()
        tab.errorMessage = nil
        tab.displayAddressText = nextURL.absoluteString

        if activeTabID == tab.id {
            navigationFallbacks = tab.navigationFallbacks
            errorMessage = nil
            displayAddressText = nextURL.absoluteString
            isSecurePage = nextURL.scheme?.lowercased() == "https"
            resetXHRTracking(for: nextURL)
        }

        webView.load(URLRequest(url: nextURL))
        return true
    }
}

extension BrowserModel: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }

        return nil
    }
}
