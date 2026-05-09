//
//  BrowserWebExtension.swift
//  macos-app
//

import Foundation
import WebKit

final class BrowserWebExtension {
    static let shared = BrowserWebExtension()

    private(set) var controller: WKWebExtensionController?
    private var context: WKWebExtensionContext?
    private weak var browser: BrowserModel?
    private var isLoadingExtension = false
    private var isLoadingBackgroundContent = false
    private var isBackgroundContentLoaded = false
    private var lastLoadError: String?
    private var lastBackgroundLoadError: String?
    private var readyCallbacks: [() -> Void] = []
    private var backgroundLoadCallbacks: [() -> Void] = []

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

    var isLoaded: Bool {
        context?.isLoaded == true
    }

    private var isReady: Bool {
        guard controller != nil else { return true }
        guard lastLoadError == nil, lastBackgroundLoadError == nil else { return true }
        return context?.isLoaded == true
            && !isLoadingExtension
            && isBackgroundContentLoaded
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
        if let browser = tab.browserModel ?? browser {
            controller.didFocusWindow(browser)
        }
        controller.didActivateTab(tab, previousActiveTab: previousTab)
        controller.didSelectTabs([tab])
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

    func prepareForNavigation(to url: URL, in tab: BrowserTabState, completion: @escaping () -> Void) {
        guard shouldPrepareDarkReader(for: url) else {
            completion()
            return
        }

        syncNavigationState(for: tab, url: url, reason: "before-background")
        performWhenReady { [weak self] in
            guard let self else {
                completion()
                return
            }

            self.loadBackgroundContent(reason: "navigation", url: url) { [weak self, weak tab] in
                if let self, let tab {
                    self.syncNavigationState(for: tab, url: url, reason: "after-background")
                }
                completion()
            }
        }
    }

    func performWhenReady(_ callback: @escaping () -> Void) {
        guard controller != nil else {
            callback()
            return
        }

        guard !isReady else {
            callback()
            return
        }

        readyCallbacks.append(callback)
        loadExtensionIfNeeded()
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
            "isLoadingBackgroundContent": isLoadingBackgroundContent,
            "backgroundContentLoaded": isBackgroundContentLoaded,
            "ready": isReady,
            "loaded": context?.isLoaded ?? false,
            "lastLoadError": lastLoadError ?? NSNull(),
            "lastBackgroundLoadError": lastBackgroundLoadError ?? NSNull()
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
        guard let controller, let extensionBaseURL = Self.extensionBaseURL else {
            lastLoadError = "Dark Reader extension not found"
            flushReadyCallbacks()
            return
        }

        isLoadingExtension = true
        isLoadingBackgroundContent = false
        isBackgroundContentLoaded = false
        lastLoadError = nil
        lastBackgroundLoadError = nil
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
                    controller.didFocusWindow(browser)
                    browser.tabStates.forEach { controller.didOpenTab($0) }
                    controller.didActivateTab(browser.activeTab)
                    controller.didSelectTabs([browser.activeTab])
                }

                self.loadBackgroundContent(reason: "initial-load", url: nil) { [weak self] in
                    self?.flushReadyCallbacks()
                }
            } catch {
                self.isLoadingExtension = false
                self.isLoadingBackgroundContent = false
                self.lastLoadError = error.localizedDescription
                self.log("load-failed error=\(error.localizedDescription)")
                self.flushReadyCallbacks()
            }
        }
    }

    private func shouldPrepareDarkReader(for url: URL) -> Bool {
        guard controller != nil,
              Self.isEnabled,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              !AppSettingsStore.shared.isDarkModeDisabled(for: url)
        else {
            return false
        }

        return true
    }

    private func syncNavigationState(for tab: BrowserTabState, url: URL, reason: String) {
        guard let controller else { return }

        tab.loadingURL = url
        if let browser = tab.browserModel ?? browser {
            controller.didFocusWindow(browser)
            controller.didActivateTab(tab, previousActiveTab: nil)
            controller.didSelectTabs([tab])
        }
        controller.didChangeTabProperties([.loading, .URL], for: tab)
        log("navigation-state-synced reason=\(reason) tab=\(String(tab.id.uuidString.prefix(8))) url=\(url.absoluteString)")
    }

    private func loadBackgroundContent(reason: String, url: URL?, completion: @escaping () -> Void) {
        guard let context else {
            completion()
            return
        }

        backgroundLoadCallbacks.append(completion)
        guard !isLoadingBackgroundContent else { return }

        isLoadingBackgroundContent = true
        Task { @MainActor in
            do {
                try await context.loadBackgroundContent()
                self.isBackgroundContentLoaded = true
                self.lastBackgroundLoadError = nil
                self.log("background-loaded reason=\(reason) url=\(url?.absoluteString ?? "nil")")
            } catch {
                self.isBackgroundContentLoaded = false
                self.lastBackgroundLoadError = error.localizedDescription
                self.log("background-load-failed reason=\(reason) url=\(url?.absoluteString ?? "nil") error=\(error.localizedDescription)")
            }

            self.isLoadingBackgroundContent = false
            self.flushBackgroundLoadCallbacks()
        }
    }

    private func flushBackgroundLoadCallbacks() {
        let callbacks = backgroundLoadCallbacks
        backgroundLoadCallbacks.removeAll()
        callbacks.forEach { $0() }
    }

    private func flushReadyCallbacks(after delay: TimeInterval = 0) {
        let callbacks = readyCallbacks
        readyCallbacks.removeAll()
        guard delay > 0 else {
            callbacks.forEach { $0() }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            callbacks.forEach { $0() }
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
        var fallbackURL: URL?
        for path in extensionCandidatePaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            let url = URL(fileURLWithPath: expandedPath, isDirectory: true)
            let manifestURL = url.appendingPathComponent("manifest.json", isDirectory: false)
            if fileManager.fileExists(atPath: manifestURL.path) {
                if manifestVersion(for: url) != 3 {
                    return url
                }
                if fallbackURL == nil {
                    fallbackURL = url
                }
            }
        }

        return fallbackURL
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
        let buildRoot = repoRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("darkreader/build", isDirectory: true)

        let repoBuildURLs = [
            buildRoot
                .appendingPathComponent("release", isDirectory: true)
                .appendingPathComponent("chrome", isDirectory: true),
            buildRoot
                .appendingPathComponent("debug", isDirectory: true)
                .appendingPathComponent("chrome", isDirectory: true),
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
        guard let manifest = manifestJSON(for: extensionBaseURL) else { return nil }

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

    private static func manifestVersion(for extensionBaseURL: URL) -> Int? {
        manifestJSON(for: extensionBaseURL)?["manifest_version"] as? Int
    }

    private static func manifestJSON(for extensionBaseURL: URL) -> [String: Any]? {
        let manifestURL = extensionBaseURL.appendingPathComponent("manifest.json", isDirectory: false)
        guard
            let data = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return manifest
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
