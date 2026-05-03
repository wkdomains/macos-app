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
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var displayAddressText = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var estimatedProgress = 0.0
    @Published private(set) var hasAttemptedNavigation = false
    @Published private(set) var historyURLs: [String]
    @Published private(set) var bookmarkURLs: [URL]
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

    private var observations: [NSKeyValueObservation] = []
    private let settingsStore: AppSettingsStore
    private var activeIdentityID: UUID?
    private var activePageHost: String?
    private var consoleRecords: [ConsoleMessageRecord] = []
    private var xhrRecords: [XHRRequestRecord] = []
    private var xhrRecordIndexesByID: [String: Int] = [:]
    private var screenshotPNG: Data?
    private var screenshotCapturedVersion = -1
    private var screenshotDirtyVersion = 0
    private var screenshotNavigationGeneration = 0
    private var screenshotIsRendering = false
    private var screenshotRenderTask: Task<Void, Never>?
    private var screenshotWaiters: [UUID: (Result<Data, Error>) -> Void] = [:]
    private var navigationFallbacks: [URL] = []

    init(
        dataStore: WKWebsiteDataStore? = nil,
        activeIdentityID: UUID? = nil,
        settingsStore: AppSettingsStore = .shared
    ) {
        self.settingsStore = settingsStore
        historyURLs = settingsStore.settings.historyURLs
        bookmarkURLs = settingsStore.bookmarkURLs
        self.activeIdentityID = activeIdentityID ?? settingsStore.activeIdentityID(for: settingsStore.startupURL)

        let initialDataStore = dataStore ?? Self.websiteDataStore(for: self.activeIdentityID)
        webView = Self.makeWebView(
            dataStore: initialDataStore,
            usesDarkMode: settingsStore.usesDarkMode(for: settingsStore.startupURL)
        )

        super.init()

        configure(webView)
        refreshSiteIdentityState()
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

    private func configure(_ webView: BrowserWKWebView) {
        webView.allowsBackForwardNavigationGestures = true
        webView.browserContextMenuDelegate = self
        webView.openBookmark = { [weak self] url in
            self?.load(url)
        }
        webView.moveBookmark = { [weak self] sourceURL, targetURL in
            self?.moveBookmark(sourceURL, to: targetURL)
        }
        syncBookmarkTitlebarState(for: webView)
        webView.viewportSizeDidChange = { [weak self] in
            self?.markScreenshotDirty(scheduleAfter: 0.25)
        }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        installPageTrackingScripts(on: webView.configuration.userContentController)

        observations = [
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.estimatedProgress = webView.estimatedProgress
                }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.isLoading = webView.isLoading
                }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.canGoBack = webView.canGoBack
                }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.canGoForward = webView.canGoForward
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
        errorMessage = nil
        navigationFallbacks = []
        webView.goBack()
    }

    func goForward() {
        guard webView.canGoForward else { return }
        errorMessage = nil
        navigationFallbacks = []
        webView.goForward()
    }

    func reload() {
        guard hasAttemptedNavigation else { return }
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

        activeIdentityID = identity.id
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

        guard nextIdentityID != activeIdentityID else { return }

        settingsStore.setActiveIdentity(nextIdentityID, for: currentURL)
        activeIdentityID = nextIdentityID
        replaceWebView(using: nextIdentityID, loading: Self.siteBaseURL(for: currentURL))
        refreshSiteIdentityState()
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

    func consoleMessages() -> [ConsoleMessageRecord] {
        consoleRecords
    }

    func currentVisiblePageScreenshotPNG(completion: @escaping (Result<Data, Error>) -> Void) {
        if let screenshotPNG,
           screenshotCapturedVersion == screenshotDirtyVersion,
           !webView.isLoading
        {
            completion(.success(screenshotPNG))
            return
        }

        guard hasAttemptedNavigation, webView.url != nil else {
            completion(.failure(ScreenshotError.noPageLoaded))
            return
        }

        let waiterID = UUID()
        screenshotWaiters[waiterID] = completion

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let completion = self?.screenshotWaiters.removeValue(forKey: waiterID) else { return }
            completion(.failure(ScreenshotError.timedOut))
        }

        guard !webView.isLoading else { return }
        scheduleScreenshotCapture(after: 0)
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
        hasAttemptedNavigation = true
        errorMessage = nil
        displayAddressText = url.absoluteString
        isSecurePage = url.scheme?.lowercased() == "https"
        navigationFallbacks = fallbackURLs
        resetXHRTracking(for: url)
        refreshDarkModeState(for: url)

        webView.load(URLRequest(url: url))
    }

    private func replaceWebView(using identityID: UUID?, loading url: URL) {
        let oldWebView = webView
        oldWebView.stopLoading()
        detach(oldWebView)
        observations.removeAll()

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
        configure(nextWebView)
        webView = nextWebView
        webViewID = UUID()
        nextWebView.load(URLRequest(url: url))
    }

    private func detach(_ webView: BrowserWKWebView) {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.browserContextMenuDelegate = nil
        webView.openBookmark = nil
        webView.moveBookmark = nil
        webView.viewportSizeDidChange = nil
        webView.removeBookmarkTitlebarAccessory()

        let userContentController = webView.configuration.userContentController
        userContentController.removeScriptMessageHandler(forName: "wkdomainsXHR")
        userContentController.removeScriptMessageHandler(forName: "wkdomainsRender")
        userContentController.removeScriptMessageHandler(forName: "wkdomainsConsole")
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

    private func syncPageState(from webView: WKWebView) {
        if let url = webView.url {
            displayAddressText = url.absoluteString
            isSecurePage = url.scheme?.lowercased() == "https"
            refreshDarkModeState(for: url)
        }

        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        estimatedProgress = webView.estimatedProgress
        isLoading = webView.isLoading
        refreshSiteIdentityState()
    }

    private func syncWindowTitle(from webView: WKWebView) {
        let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            self.webView.browserWindowTitle = title
        } else {
            self.webView.browserWindowTitle = BrowserWKWebView.defaultWindowTitle
        }
    }

    private func recordVisitedURL(_ url: URL) {
        settingsStore.updateLastVisitedURL(url, identityID: activeIdentityID)
        historyURLs = settingsStore.settings.historyURLs
        refreshSiteIdentityState()
    }

    private func refreshSiteIdentityState() {
        currentIdentityName = settingsStore.identityName(for: activeIdentityID)
        siteIdentityMenuItems = settingsStore.siteIdentityMenuItems(
            for: webView.url,
            activeIdentityID: activeIdentityID
        )
    }

    private func syncBookmarkState() {
        bookmarkURLs = settingsStore.bookmarkURLs
        syncBookmarkTitlebarState(for: webView)
    }

    private func syncBookmarkTitlebarState(for webView: BrowserWKWebView) {
        webView.bookmarkURLs = settingsStore.bookmarkURLs
    }

    private func refreshDarkModeState(for url: URL?) {
        webView.configureForcedDarkPageBackground(settingsStore.usesDarkMode(for: url))
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

    private func installPageTrackingScripts(on userContentController: WKUserContentController) {
        userContentController.add(self, name: "wkdomainsXHR")
        userContentController.add(self, name: "wkdomainsRender")
        userContentController.add(self, name: "wkdomainsConsole")
        installPageTrackingUserScripts(on: userContentController)
    }

    private func reinstallPageTrackingUserScripts() {
        let userContentController = webView.configuration.userContentController
        userContentController.removeAllUserScripts()
        installPageTrackingUserScripts(on: userContentController)
    }

    private func installPageTrackingUserScripts(on userContentController: WKUserContentController) {
        userContentController.addUserScript(
            WKUserScript(
                source: Self.xhrTrackingScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        userContentController.addUserScript(
            WKUserScript(
                source: Self.renderInvalidationScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        if settingsStore.settings.dark {
            userContentController.addUserScript(
                WKUserScript(
                    source: Self.forcedDarkModeScript(disabledSites: settingsStore.darkDisabledSites),
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        }
        userContentController.addUserScript(
            WKUserScript(
                source: Self.consoleTrackingScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
    }

    private func resetScreenshotForNavigation() {
        screenshotNavigationGeneration += 1
        screenshotDirtyVersion += 1
        screenshotCapturedVersion = -1
        screenshotPNG = nil
        screenshotRenderTask?.cancel()
        screenshotRenderTask = nil
    }

    private func markScreenshotDirty(scheduleAfter delay: TimeInterval) {
        guard hasAttemptedNavigation, webView.url != nil else { return }

        screenshotDirtyVersion += 1

        guard !screenshotWaiters.isEmpty else { return }
        guard !webView.isLoading else { return }
        scheduleScreenshotCapture(after: delay)
    }

    private func scheduleScreenshotCapture(after delay: TimeInterval) {
        guard hasAttemptedNavigation, webView.url != nil else { return }

        screenshotRenderTask?.cancel()
        let generation = screenshotNavigationGeneration
        let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)

        screenshotRenderTask = Task { @MainActor [weak self] in
            if nanoseconds > 0 {
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled,
                  let self,
                  self.screenshotNavigationGeneration == generation
            else {
                return
            }

            self.captureVisiblePageScreenshot(generation: generation)
        }
    }

    private func captureVisiblePageScreenshot(generation: Int) {
        guard !screenshotIsRendering else { return }
        guard !webView.isLoading else { return }
        guard webView.bounds.width >= 1, webView.bounds.height >= 1 else {
            finishScreenshotWaiters(with: .failure(ScreenshotError.webViewNotVisible))
            return
        }

        screenshotIsRendering = true
        let capturedVersion = screenshotDirtyVersion
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds

        webView.takeSnapshot(with: configuration) { [weak self] image, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.screenshotIsRendering = false

                guard self.screenshotNavigationGeneration == generation else {
                    if !self.webView.isLoading {
                        self.scheduleScreenshotCapture(after: 0.2)
                    }
                    return
                }

                if let error {
                    self.finishScreenshotWaiters(with: .failure(error))
                    return
                }

                guard let image,
                      let pngData = Self.pngData(from: image)
                else {
                    self.finishScreenshotWaiters(with: .failure(ScreenshotError.pngEncodingFailed))
                    return
                }

                self.screenshotPNG = pngData
                self.screenshotCapturedVersion = capturedVersion

                if self.screenshotCapturedVersion == self.screenshotDirtyVersion {
                    self.finishScreenshotWaiters(with: .success(pngData))
                } else {
                    self.scheduleScreenshotCapture(after: 0.15)
                }
            }
        }
    }

    private func finishScreenshotWaiters(with result: Result<Data, Error>) {
        let waiters = Array(screenshotWaiters.values)
        screenshotWaiters.removeAll()

        for completion in waiters {
            completion(result)
        }
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}

private enum ScreenshotError: LocalizedError {
    case noPageLoaded
    case pngEncodingFailed
    case timedOut
    case webViewNotVisible

    var errorDescription: String? {
        switch self {
        case .noPageLoaded:
            return "No page is loaded."
        case .pngEncodingFailed:
            return "Could not encode the screenshot as PNG."
        case .timedOut:
            return "Timed out waiting for the screenshot to be rendered."
        case .webViewNotVisible:
            return "The web view is not visible."
        }
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
        default:
            return
        }
    }
}

extension BrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorMessage = nil
        hasAttemptedNavigation = true
        isLoading = true
        estimatedProgress = max(0.08, webView.estimatedProgress)
        resetScreenshotForNavigation()
        resetXHRTracking(for: webView.url)
        syncPageState(from: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        errorMessage = nil
        navigationFallbacks = []
        syncPageState(from: webView)

        if let url = webView.url {
            recordVisitedURL(url)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        errorMessage = nil
        estimatedProgress = 1
        syncPageState(from: webView)
        markScreenshotDirty(scheduleAfter: 0.25)
        botTerminal.refreshIfOpen(
            currentURL: webView.url,
            pageTitle: webView.title,
            viewportMode: viewportMode,
            xhrCount: xhrRecords.count
        )

        if let url = webView.url {
            recordVisitedURL(url)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if loadNextFallback(after: error) {
            return
        }

        handleNavigationError(error)
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

        refreshDarkModeState(for: url)
        decisionHandler(.allow)
    }

    private func handleNavigationError(_ error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }

        navigationFallbacks = []
        isLoading = false
        estimatedProgress = 0
        errorMessage = error.localizedDescription
        finishScreenshotWaiters(with: .failure(error))
    }

    private func loadNextFallback(after error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled,
              !navigationFallbacks.isEmpty
        else {
            return false
        }

        let nextURL = navigationFallbacks.removeFirst()
        errorMessage = nil
        displayAddressText = nextURL.absoluteString
        isSecurePage = nextURL.scheme?.lowercased() == "https"
        resetXHRTracking(for: nextURL)
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
