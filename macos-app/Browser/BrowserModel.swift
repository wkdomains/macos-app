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

final class BrowserModel: NSObject, ObservableObject {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var displayAddressText = ""
    @Published var errorMessage: String?
    @Published var estimatedProgress = 0.0
    @Published var hasAttemptedNavigation = false
    @Published var historyURLs: [String]
    @Published var bookmarkURLs: [URL]
    @Published var tabs: [BrowserTabItem] = []
    @Published var activeTabID: UUID
    @Published var isLoading = false
    @Published var isSecurePage = false
    @Published var pageFindRequestID = UUID()
    @Published var currentIdentityName = "Default"
    @Published var siteIdentityMenuItems: [BrowserSiteIdentityMenuItem] = [
        BrowserSiteIdentityMenuItem(id: BrowserSiteIdentityMenuItem.defaultID, title: "Default", isCurrent: true)
    ]
    @Published var viewportMode: BrowserViewportMode = .desktop

    @Published var webView: BrowserWKWebView
    let botTerminal = BotTerminalModel()

    var tabStates: [BrowserTabState]
    private let loginStore: LoginStore
    let settingsStore: AppSettingsStore
    private var activePageHost: String?
    private var pendingLoginUsernameTarget: LoginFieldTarget?
    private var pendingLoginPasswordTarget: LoginFieldTarget?
    var consoleRecords: [ConsoleMessageRecord] = []
    var xhrRecords: [XHRRequestRecord] = []
    var xhrRecordIndexesByID: [String: Int] = [:]
    var lastTimingPageURL: String?
    var lastTimingIsLoading: Bool?
    var lastTimingProgressBucket: Int?
    var screenshotPNG: Data?
    var screenshotCapturedVersion = -1
    var screenshotDirtyVersion = 0
    var screenshotNavigationGeneration = 0
    var screenshotIsRendering = false
    var screenshotRenderTask: Task<Void, Never>?
    var screenshotWaiters: [UUID: (Result<Data, Error>) -> Void] = [:]
    var navigationFallbacks: [URL] = []

    init(
        dataStore: WKWebsiteDataStore? = nil,
        activeIdentityID: UUID? = nil,
        settingsStore: AppSettingsStore = .shared
    ) {
        self.settingsStore = settingsStore
        loginStore = LoginStore(directoryURL: settingsStore.directoryURL)
        historyURLs = settingsStore.settings.historyURLs
        bookmarkURLs = settingsStore.bookmarkURLs
        let startupURLs = settingsStore.startupURLs
        let startupTabPins = settingsStore.startupTabPins
        let startupActiveTabIndex = settingsStore.startupActiveTabIndex
        let initialTabs = startupURLs.enumerated().map { index, startupURL in
            let identityID = index == startupActiveTabIndex
                ? activeIdentityID ?? settingsStore.activeIdentityID(for: startupURL)
                : settingsStore.activeIdentityID(for: startupURL)
            let webViewDataStore: WKWebsiteDataStore
            if index == startupActiveTabIndex, let dataStore {
                webViewDataStore = dataStore
            } else {
                webViewDataStore = Self.websiteDataStore(for: identityID)
            }
            let webView = Self.makeWebView(
                dataStore: webViewDataStore,
                usesDarkMode: settingsStore.usesDarkMode(for: startupURL)
            )

            return BrowserTabState(
                webView: webView,
                cookiePersistence: BrowserCookiePersistence(directoryURL: settingsStore.directoryURL),
                identityID: identityID,
                isPinned: startupTabPins.indices.contains(index) ? startupTabPins[index] : false
            )
        }
        let initialTab = initialTabs[startupActiveTabIndex]
        tabStates = initialTabs
        activeTabID = initialTab.id
        initialTab.webView.isActiveBrowserTab = true
        webView = initialTab.webView

        super.init()

        for tab in tabStates {
            configure(tab)
        }
        refreshSiteIdentityState()
        refreshPublishedTabs()
        for tab in tabStates {
            attachCookiePersistence(to: tab)
        }
    }

    static func websiteDataStore(for identityID: UUID?) -> WKWebsiteDataStore {
        guard let identityID else {
            BrowserSessionDiagnostics.log(
                "webkit data store selected profile=default kind=default",
                directoryURL: AppSettingsStore.shared.directoryURL
            )
            return defaultWebsiteDataStore
        }

        if let dataStore = websiteDataStoresByIdentityID[identityID] {
            BrowserSessionDiagnostics.log(
                "webkit data store selected profile=\(identityID.uuidString.lowercased()) kind=identity cached=true",
                directoryURL: AppSettingsStore.shared.directoryURL
            )
            return dataStore
        }

        let dataStore = WKWebsiteDataStore(forIdentifier: identityID)
        websiteDataStoresByIdentityID[identityID] = dataStore
        BrowserSessionDiagnostics.log(
            "webkit data store selected profile=\(identityID.uuidString.lowercased()) kind=identity cached=false",
            directoryURL: AppSettingsStore.shared.directoryURL
        )
        return dataStore
    }

    private static let defaultWebsiteDataStore = WKWebsiteDataStore.default()
    private static var websiteDataStoresByIdentityID: [UUID: WKWebsiteDataStore] = [:]

    static func makeWebView(dataStore: WKWebsiteDataStore, usesDarkMode: Bool) -> BrowserWKWebView {
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

    func configure(_ tab: BrowserTabState) {
        let webView = tab.webView
        webView.allowsBackForwardNavigationGestures = true
        webView.browserContextMenuDelegate = self
        webView.selectTab = { [weak self] tabID in
            self?.selectTab(tabID)
        }
        webView.addTab = { [weak self] in
            self?.addEmptyTab()
        }
        webView.moveTab = { [weak self] sourceID, targetID in
            self?.moveTab(sourceID, to: targetID)
        }
        webView.togglePinnedTab = { [weak self] tabID in
            self?.togglePinnedTab(tabID)
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

    func findInPage(
        _ query: String,
        backwards: Bool = false,
        completion: ((Bool) -> Void)? = nil
    ) {
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true

        webView.find(query, configuration: configuration) { result in
            completion?(result.matchFound)
        }
    }

    func clearPageFind() {
        let configuration = WKFindConfiguration()
        webView.find("", configuration: configuration) { _ in }
    }

    func requestPageFind() {
        pageFindRequestID = UUID()
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
        saveAllProfileCookiesNow()
    }

    func saveAllProfileCookiesNow(completion: (() -> Void)? = nil) {
        BrowserCookiePersistence.saveAllProfileCookies(completion: completion)
    }

    func clearCookiesForCurrentDomain() {
        guard let host = webView.url?.host?.lowercased() else { return }
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let cookiePersistence = activeTab.cookiePersistence

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

            cookiePersistence.removePersistedCookies(matchingHost: host)
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
        fillSavedLoginForCurrentSite(reportsMissingLogin: true, remainingAttempts: 4)
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
        load(url, in: activeTab, fallbackURLs: fallbackURLs)
    }

    func load(_ url: URL, in tab: BrowserTabState, fallbackURLs: [URL]) {
        prepareForLoad(url, in: tab, fallbackURLs: fallbackURLs)

        guard tab.isCookieStoreReady else {
            tab.pendingLoadRequest = (url, fallbackURLs)
            return
        }

        tab.webView.load(URLRequest(url: url))
    }

    private func prepareForLoad(_ url: URL, in tab: BrowserTabState, fallbackURLs: [URL]) {
        tab.hasAttemptedNavigation = true
        tab.errorMessage = nil
        tab.displayAddressText = url.absoluteString
        tab.navigationFallbacks = fallbackURLs

        guard activeTabID == tab.id else {
            refreshPublishedTabs()
            persistOpenTabs()
            return
        }

        hasAttemptedNavigation = true
        errorMessage = nil
        displayAddressText = url.absoluteString
        isSecurePage = url.scheme?.lowercased() == "https"
        navigationFallbacks = fallbackURLs
        resetXHRTracking(for: url)
        refreshDarkModeState(for: url)
        refreshPublishedTabs()
        persistOpenTabs()
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
        webView.isActiveBrowserTab = true
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

    func attachCookiePersistence(
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

    func detach(_ webView: BrowserWKWebView) {
        webView.isActiveBrowserTab = false
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.browserContextMenuDelegate = nil
        webView.selectTab = nil
        webView.addTab = nil
        webView.moveTab = nil
        webView.togglePinnedTab = nil
        webView.viewportSizeDidChange = nil
        webView.removeTitlebarTabsAccessory()

        let userContentController = webView.configuration.userContentController
        userContentController.removeScriptMessageHandler(forName: "wkdomainsXHR")
        userContentController.removeScriptMessageHandler(forName: "wkdomainsRender")
        userContentController.removeScriptMessageHandler(forName: "wkdomainsConsole")
        if Self.darkModeUsesIsolatedContentWorld {
            userContentController.removeScriptMessageHandler(forName: "wkdomainsConsole", contentWorld: Self.darkModeContentWorld)
        }
        userContentController.removeScriptMessageHandler(forName: "wkdomainsLogin")
    }

    func resetXHRTracking(for url: URL?) {
        activePageHost = url?.host?.lowercased()
        xhrRecords.removeAll(keepingCapacity: true)
        xhrRecordIndexesByID.removeAll(keepingCapacity: true)
        consoleRecords.removeAll(keepingCapacity: true)
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

    func saveCapturedLogin(_ message: [String: Any]) {
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

    func fillSavedLoginForCurrentSite(reportsMissingLogin: Bool, remainingAttempts: Int = 4) {
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

                let filled = Self.intValue(from: value) ?? 0
                if filled < 2,
                   remainingAttempts > 0
                {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                        self?.fillSavedLoginForCurrentSite(
                            reportsMissingLogin: reportsMissingLogin,
                            remainingAttempts: remainingAttempts - 1
                        )
                    }
                    return
                }

                if reportsMissingLogin,
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

    func showAlert(message: String, detail: String) {
        guard let window = webView.window else { return }

        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    func refreshSiteIdentityState() {
        currentIdentityName = settingsStore.identityName(for: activeTab.identityID)
        siteIdentityMenuItems = settingsStore.siteIdentityMenuItems(
            for: webView.url,
            activeIdentityID: activeTab.identityID
        )
    }

    private func syncBookmarkState() {
        bookmarkURLs = settingsStore.bookmarkURLs
    }

    func refreshDarkModeState(for url: URL?) {
        webView.configureForcedDarkPageBackground(settingsStore.usesDarkMode(for: url))
    }

    static func xhrResponseByteSortKey(_ record: XHRRequestRecord) -> Int {
        record.responseBytes ?? -1
    }

    private static let xhrMenuByteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        return formatter
    }()

    static func xhrMenuTitle(for record: XHRRequestRecord, at index: Int) -> String {
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

    static func xhrMenuURLTitle(_ rawURL: String) -> String {
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

    static func normalizedHost(_ host: String) -> String {
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

    static func host(_ host: String, matches requestedHost: String) -> Bool {
        let host = normalizedHost(host)

        return host == requestedHost
            || host.hasSuffix(".\(requestedHost)")
            || requestedHost.hasSuffix(".\(host)")
    }

    static func intValue(from value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return nil
    }

    static func stringDictionary(from value: Any?) -> [String: String] {
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
