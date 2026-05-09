//
//  BrowserModel+WebKitDelegates.swift
//  macos-app
//

import AppKit
import Foundation
import WebKit

extension BrowserModel: BrowserContextMenuDelegate {}

extension BrowserModel: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let startedAt = BrowserDebugLogging.timestamp()
        defer {
            BrowserDebugLogging.logSlowOperation(
                "script-message",
                since: startedAt,
                threshold: 0.02,
                details: "name=\(message.name) bodyType=\(String(describing: type(of: message.body)))"
            )
        }

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
        if activeTabID == tab.id {
            BrowserDebugLogging.startTimingSession(
                pageURL: webView.url?.absoluteString,
                pageHost: webView.url?.host,
                reason: "navigation-start"
            )
        }
        logNavigationEvent("didStartProvisionalNavigation", webView: webView, tab: tab)

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
        logNavigationEvent("didCommit", webView: webView, tab: tab)

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
        logNavigationEvent("didFinish", webView: webView, tab: tab)

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
        logNavigationFailure("didFail", webView: webView, error: error)
        handleNavigationError(error, in: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logNavigationFailure("didFailProvisionalNavigation", webView: webView, error: error)
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

        if navigationAction.targetFrame?.isMainFrame != false {
            BrowserDebugLogging.log(
                "[wkdomains-debug] navigation policy allow url=\(url.absoluteString) type=\(navigationAction.navigationType.rawValue)"
            )
        }
        decisionHandler(.allow)
    }

    private func logNavigationEvent(_ event: String, webView: WKWebView, tab: BrowserTabState) {
        BrowserDebugLogging.log(
            "[wkdomains-debug] navigation \(event) tab=\(String(tab.id.uuidString.prefix(8))) url=\(webView.url?.absoluteString ?? "nil") loading=\(webView.isLoading) progress=\(String(format: "%.3f", webView.estimatedProgress)) title=\(webView.title ?? "nil")"
        )
    }

    private func logNavigationFailure(_ event: String, webView: WKWebView, error: Error) {
        let nsError = error as NSError
        BrowserDebugLogging.log(
            "[wkdomains-debug] navigation \(event) url=\(webView.url?.absoluteString ?? "nil") domain=\(nsError.domain) code=\(nsError.code) message=\(error.localizedDescription)"
        )
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
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = javascriptDialog(
            message: "Alert from \(displayHost(for: frame))",
            detail: message,
            style: .informational
        )
        alert.addButton(withTitle: "OK")

        present(alert, for: webView) { _ in
            completionHandler()
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = javascriptDialog(
            message: "Confirm action on \(displayHost(for: frame))",
            detail: message,
            style: .warning
        )
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        present(alert, for: webView) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let input = NSTextField(string: defaultText ?? "")
        input.lineBreakMode = .byTruncatingTail
        input.placeholderString = prompt
        input.frame = NSRect(x: 0, y: 0, width: 320, height: 24)

        let alert = javascriptDialog(
            message: "Prompt from \(displayHost(for: frame))",
            detail: prompt,
            style: .informational
        )
        alert.accessoryView = input
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        present(alert, for: webView) { response in
            completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let openPanel = NSOpenPanel()
        let choosesDirectories = parameters.allowsDirectories

        openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
        openPanel.canChooseDirectories = choosesDirectories
        openPanel.canChooseFiles = !choosesDirectories
        openPanel.canCreateDirectories = false
        openPanel.resolvesAliases = true
        openPanel.prompt = choosesDirectories ? "Choose Folder" : "Choose Files"
        openPanel.message = choosesDirectories
            ? "Choose a folder to upload."
            : "Choose files to upload."

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            completionHandler(response == .OK ? openPanel.urls : nil)
        }

        if let window = webView.window {
            openPanel.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(openPanel.runModal())
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil,
           let url = navigationAction.request.url {
            if let scheme = url.scheme?.lowercased(), ["http", "https", "about"].contains(scheme) {
                addTab(loading: url)
            } else {
                NSWorkspace.shared.open(url)
            }
        }

        return nil
    }

    private func javascriptDialog(message: String, detail: String, style: NSAlert.Style) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = style
        return alert
    }

    private func present(
        _ alert: NSAlert,
        for webView: WKWebView,
        completionHandler: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        if let window = webView.window {
            alert.beginSheetModal(for: window, completionHandler: completionHandler)
        } else {
            completionHandler(alert.runModal())
        }
    }

    private func displayHost(for frame: WKFrameInfo) -> String {
        frame.request.url?.host ?? webView.url?.host ?? "this page"
    }
}

final class BrowserWebExtension {
    static let shared = BrowserWebExtension()

    private(set) var controller: WKWebExtensionController?
    private var context: WKWebExtensionContext?
    private weak var browser: BrowserModel?
    private var isLoadingExtension = false
    private var lastLoadError: String?

    private init() {
        guard Self.isEnabled else { return }

        let configuration = WKWebExtensionController.Configuration(identifier: Self.storageIdentifier)
        configuration.defaultWebsiteDataStore = WKWebsiteDataStore.default()
        controller = WKWebExtensionController(configuration: configuration)
        log("controller-created path=\(Self.extensionBaseURL?.path ?? "nil")")
    }

    static func configure(_ configuration: WKWebViewConfiguration) {
        guard let controller = shared.controller else { return }
        configuration.webExtensionController = controller
    }

    var isAvailable: Bool {
        Self.extensionBaseURL != nil
    }

    func attach(browser: BrowserModel) {
        guard let controller else { return }

        self.browser = browser
        controller.delegate = browser
        browser.tabStates.forEach { $0.browserModel = browser }
        loadExtensionIfNeeded()
    }

    func didOpenTab(_ tab: BrowserTabState) {
        guard let controller else { return }
        controller.didOpenTab(tab)
    }

    func didCloseTab(_ tab: BrowserTabState) {
        guard let controller else { return }
        controller.didCloseTab(tab)
    }

    func didActivateTab(_ tab: BrowserTabState, previousTab: BrowserTabState?) {
        guard let controller else { return }
        controller.didActivateTab(tab, previousActiveTab: previousTab)
    }

    func didChangeTab(_ tab: BrowserTabState, properties: WKWebExtension.TabChangedProperties) {
        guard let controller else { return }
        controller.didChangeTabProperties(properties, for: tab)
    }

    func updateDeniedSites(_ disabledSites: [String]) {
        guard let context else { return }
        context.deniedPermissionMatchPatterns = Self.deniedPermissionMatchPatterns(for: disabledSites)
        log("updated-denied-sites count=\(disabledSites.count) patterns=\(context.deniedPermissionMatchPatterns.count)")
    }

    var status: [String: Any] {
        var response: [String: Any] = [
            "enabled": Self.isEnabled,
            "globalDarkSetting": AppSettingsStore.shared.isGlobalDarkModeEnabled,
            "disabledSites": AppSettingsStore.shared.darkDisabledSites,
            "selectedExtensionPath": Self.extensionBaseURL?.path ?? NSNull(),
            "candidateExtensionPaths": Self.extensionCandidatePaths,
            "manifest": Self.manifestSummary(for: Self.extensionBaseURL) ?? NSNull(),
            "controllerCreated": controller != nil,
            "controllerExtensionContextCount": controller?.extensionContexts.count ?? 0,
            "isLoadingExtension": isLoadingExtension,
            "loaded": context?.isLoaded ?? false,
            "lastLoadError": lastLoadError ?? NSNull()
        ]

        if let context {
            response["baseURL"] = context.baseURL.absoluteString
            response["uniqueIdentifier"] = context.uniqueIdentifier
            response["isInspectable"] = context.isInspectable
            response["contextErrors"] = context.errors.map { error in
                let nsError = error as NSError
                return [
                    "domain": nsError.domain,
                    "code": nsError.code,
                    "message": nsError.localizedDescription
                ] as [String: Any]
            }
            response["currentPermissions"] = context.currentPermissions.map(\.rawValue).sorted()
            response["currentPermissionMatchPatterns"] = context.currentPermissionMatchPatterns.map { $0.string }.sorted()
            response["deniedPermissionMatchPatterns"] = context.deniedPermissionMatchPatterns.keys.map { $0.string }.sorted()

            let webExtension = context.webExtension
            response["webExtension"] = [
                "displayName": webExtension.displayName ?? NSNull(),
                "version": webExtension.version ?? NSNull(),
                "requestedPermissions": webExtension.requestedPermissions.map(\.rawValue).sorted(),
                "requestedPermissionMatchPatterns": webExtension.requestedPermissionMatchPatterns.map { $0.string }.sorted(),
                "allRequestedMatchPatterns": webExtension.allRequestedMatchPatterns.map { $0.string }.sorted()
            ] as [String: Any]
        } else {
            response["contextErrors"] = []
        }

        return response
    }

    private func loadExtensionIfNeeded() {
        guard context == nil, !isLoadingExtension else { return }
        guard let controller, let extensionBaseURL = Self.extensionBaseURL else { return }

        isLoadingExtension = true
        lastLoadError = nil
        Task { @MainActor in
            do {
                let webExtension = try await WKWebExtension(resourceBaseURL: extensionBaseURL)
                let context = WKWebExtensionContext(for: webExtension)
                context.uniqueIdentifier = "com.wkdomains.darkreader"
                context.baseURL = URL(string: "webkit-extension://darkreader.wkdomains")!
                context.isInspectable = true
                context.inspectionName = "Dark Reader"
                context.grantedPermissions = Dictionary(
                    uniqueKeysWithValues: webExtension.requestedPermissions.map { ($0, Date.distantFuture) }
                )
                context.grantedPermissionMatchPatterns = Dictionary(
                    uniqueKeysWithValues: webExtension.allRequestedMatchPatterns.map { ($0, Date.distantFuture) }
                )
                context.deniedPermissionMatchPatterns = Self.deniedPermissionMatchPatterns(
                    for: AppSettingsStore.shared.darkDisabledSites
                )

                try controller.load(context)
                self.context = context
                self.isLoadingExtension = false
                self.log("loaded name=\(webExtension.displayName ?? "Dark Reader") permissions=\(webExtension.requestedPermissions.count) patterns=\(webExtension.allRequestedMatchPatterns.count)")

                if let browser {
                    controller.didOpenWindow(browser)
                    browser.tabStates.forEach { controller.didOpenTab($0) }
                    controller.didActivateTab(browser.activeTab)
                }
            } catch {
                self.isLoadingExtension = false
                self.lastLoadError = error.localizedDescription
                self.log("load-failed error=\(error.localizedDescription)")
            }
        }
    }

    private static var isEnabled: Bool {
        guard AppSettingsStore.shared.isGlobalDarkModeEnabled else {
            return false
        }

        return extensionBaseURL != nil
    }

    private static var extensionBaseURL: URL? {
        let fileManager = FileManager.default
        for path in extensionCandidatePaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            let url = URL(fileURLWithPath: expandedPath, isDirectory: true)
            let manifestURL = url.appendingPathComponent("manifest.json", isDirectory: false)
            if fileManager.fileExists(atPath: manifestURL.path) {
                return url
            }
        }

        return nil
    }

    private static var extensionCandidatePaths: [String] {
        let rawPaths = [
            ProcessInfo.processInfo.environment["WKDOMAINS_DARK_READER_EXTENSION_PATH"],
            UserDefaults.standard.string(forKey: "wkdomains.darkReaderWebExtensionPath")
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) } + defaultExtensionBaseURLs.map(\.path)

        var seenPaths = Set<String>()
        return rawPaths.filter { path in
            !path.isEmpty && seenPaths.insert(path).inserted
        }
    }

    private static var defaultExtensionBaseURLs: [URL] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let buildRoot = repoRoot
            .deletingLastPathComponent()
            .appendingPathComponent("darkreader/build", isDirectory: true)

        let repoBuildURLs = [
            buildRoot
                .appendingPathComponent("release", isDirectory: true)
                .appendingPathComponent("chrome-mv3", isDirectory: true),
            buildRoot
                .appendingPathComponent("debug", isDirectory: true)
                .appendingPathComponent("chrome-mv3", isDirectory: true)
        ]

        guard let resourceURL = Bundle.main.resourceURL else {
            return repoBuildURLs
        }

        return [
            resourceURL.appendingPathComponent("DarkReaderWebExtension", isDirectory: true)
        ] + repoBuildURLs
    }

    private static func manifestSummary(for extensionBaseURL: URL?) -> [String: Any]? {
        guard let extensionBaseURL else { return nil }

        let manifestURL = extensionBaseURL.appendingPathComponent("manifest.json", isDirectory: false)
        guard
            let data = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return [
            "name": manifest["name"] as? String ?? NSNull(),
            "version": manifest["version"] as? String ?? NSNull(),
            "manifestVersion": manifest["manifest_version"] as? Int ?? NSNull(),
            "permissions": manifest["permissions"] as? [String] ?? [],
            "hostPermissions": manifest["host_permissions"] as? [String] ?? [],
            "contentScriptCount": (manifest["content_scripts"] as? [[String: Any]])?.count ?? 0,
            "hasBackground": manifest["background"] != nil
        ]
    }

    private static func deniedPermissionMatchPatterns(for disabledSites: [String]) -> [WKWebExtension.MatchPattern: Date] {
        var deniedPatterns: [WKWebExtension.MatchPattern: Date] = [:]
        for site in disabledSites {
            for pattern in disabledSiteMatchPatterns(for: site) {
                deniedPatterns[pattern] = Date.distantFuture
            }
        }
        return deniedPatterns
    }

    private static func disabledSiteMatchPatterns(for site: String) -> [WKWebExtension.MatchPattern] {
        let host = site
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty else { return [] }

        var patterns: [WKWebExtension.MatchPattern] = []
        if let exactPattern = try? WKWebExtension.MatchPattern(scheme: "*", host: host, path: "/*") {
            patterns.append(exactPattern)
        }

        if host != "localhost",
           !host.contains(":"),
           host.rangeOfCharacter(from: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")) != nil
        {
            if let wildcardPattern = try? WKWebExtension.MatchPattern(scheme: "*", host: "*.\(host)", path: "/*") {
                patterns.append(wildcardPattern)
            }
        }

        return patterns
    }

    private static let storageIdentifier = UUID(uuidString: "8A4EA12B-CE67-4B78-8C79-7F16C3975B4D")!

    private func log(_ message: String) {
        BrowserDebugLogging.log("[wkdomains-debug] darkreader-webextension \(message)")
    }
}

extension BrowserModel: WKWebExtensionControllerDelegate, WKWebExtensionWindow {
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        [self]
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        self
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionTab)?, Error?) -> Void
    ) {
        let tab = makeTab(initialURL: configuration.url)
        tab.isPinned = configuration.shouldBePinned
        tabStates.append(tab)
        attachCookiePersistence(to: tab)

        if let url = configuration.url {
            load(url, in: tab, fallbackURLs: [])
        }

        if configuration.shouldBeActive {
            selectTab(tab.id)
        } else {
            refreshPublishedTabs()
            persistOpenTabs()
        }

        BrowserWebExtension.shared.didOpenTab(tab)
        completionHandler(tab, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, Error?) -> Void
    ) {
        if let url = configuration.tabURLs.first {
            addTab(loading: url)
        } else {
            addEmptyTab()
        }
        completionHandler(self, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        if let url = extensionContext.optionsPageURL {
            addTab(loading: url)
        }
        completionHandler(nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
    ) {
        completionHandler(permissions, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        completionHandler(urls, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
    ) {
        completionHandler(matchPatterns, nil)
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        tabStates.map { $0 as any WKWebExtensionTab }
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        activeTab
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType {
        .normal
    }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window = webView.window else { return .normal }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        if window.isMiniaturized { return .minimized }
        if window.isZoomed { return .maximized }
        return .normal
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool {
        false
    }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        webView.window?.screen?.frame ?? .null
    }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        webView.window?.frame ?? .null
    }

    func focus(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        webView.window?.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }
}

extension BrowserTabState: WKWebExtensionTab {
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        browserModel
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        browserModel?.tabStates.firstIndex { $0 === self } ?? NSNotFound
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        guard webView.configuration.webExtensionController === context.webExtensionController else { return nil }
        return webView
    }

    func title(for context: WKWebExtensionContext) -> String? {
        title
    }

    func isPinned(for context: WKWebExtensionContext) -> Bool {
        isPinned
    }

    func setPinned(_ pinned: Bool, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        browserModel?.setTab(id, pinned: pinned)
        completionHandler(nil)
    }

    func size(for context: WKWebExtensionContext) -> CGSize {
        webView.bounds.size
    }

    func url(for context: WKWebExtensionContext) -> URL? {
        webView.url
    }

    func pendingURL(for context: WKWebExtensionContext) -> URL? {
        pendingLoadRequest?.url ?? (webView.isLoading ? webView.url : nil)
    }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool {
        !webView.isLoading
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        browserModel?.load(url, in: self, fallbackURLs: [])
        completionHandler(nil)
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if fromOrigin {
            webView.reloadFromOrigin()
        } else {
            webView.reload()
        }
        completionHandler(nil)
    }

    func goBack(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if webView.canGoBack {
            webView.goBack()
        }
        completionHandler(nil)
    }

    func goForward(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if webView.canGoForward {
            webView.goForward()
        }
        completionHandler(nil)
    }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        browserModel?.selectTab(id)
        completionHandler(nil)
    }

    func isSelected(for context: WKWebExtensionContext) -> Bool {
        browserModel?.activeTabID == id
    }

    func setSelected(_ selected: Bool, for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        if selected {
            browserModel?.selectTab(id)
        }
        completionHandler(nil)
    }

    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool {
        true
    }

    func shouldBypassPermissions(for context: WKWebExtensionContext) -> Bool {
        true
    }
}
