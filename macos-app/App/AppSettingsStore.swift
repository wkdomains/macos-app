//
//  AppSettingsStore.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import Darwin
import Foundation

struct SiteIdentity: Codable, Identifiable, Equatable {
    var id: UUID
    var siteKey: String
    var name: String
    var lastURL: String?
    var createdAt: Date
    var lastUsedAt: Date
}

struct BrowserSiteIdentityMenuItem: Identifiable, Equatable {
    static let defaultID = "default"

    var id: String
    var title: String
    var isCurrent: Bool
}

struct AppSettings: Codable {
    static let defaultPort: UInt16 = 9001
    static let defaultURL = "https://wkdomains.com"
    static let maxHistoryCount = 30

    var bookmarks: [String]
    var port: UInt16
    var lastURL: String
    var lastDomain: String
    var openTabs: [String]
    var openTabPins: [Bool]
    var activeTabIndex: Int
    var historyURLs: [String]
    var dark: Bool
    var darkDisabledSites: [String]
    var siteIdentities: [String: [SiteIdentity]]
    var activeSiteIdentityIDs: [String: UUID]

    static var defaults: AppSettings {
        AppSettings(
            bookmarks: [],
            port: defaultPort,
            lastURL: defaultURL,
            lastDomain: URL(string: defaultURL)?.host ?? "wkdomains.com",
            openTabs: [defaultURL],
            openTabPins: [false],
            activeTabIndex: 0,
            historyURLs: [defaultURL],
            dark: true,
            darkDisabledSites: [],
            siteIdentities: [:],
            activeSiteIdentityIDs: [:]
        )
    }

    init(
        bookmarks: [String],
        port: UInt16,
        lastURL: String,
        lastDomain: String,
        openTabs: [String],
        openTabPins: [Bool],
        activeTabIndex: Int,
        historyURLs: [String],
        dark: Bool,
        darkDisabledSites: [String],
        siteIdentities: [String: [SiteIdentity]],
        activeSiteIdentityIDs: [String: UUID]
    ) {
        self.bookmarks = bookmarks
        self.port = port
        self.lastURL = lastURL
        self.lastDomain = lastDomain
        self.openTabs = openTabs
        self.openTabPins = openTabPins
        self.activeTabIndex = activeTabIndex
        self.historyURLs = historyURLs
        self.dark = dark
        self.darkDisabledSites = darkDisabledSites
        self.siteIdentities = siteIdentities
        self.activeSiteIdentityIDs = activeSiteIdentityIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        bookmarks = try container.decodeIfPresent([String].self, forKey: .bookmarks) ?? []
        port = try container.decodeIfPresent(UInt16.self, forKey: .port) ?? Self.defaultPort
        lastURL = try container.decodeIfPresent(String.self, forKey: .lastURL) ?? Self.defaultURL
        lastDomain = try container.decodeIfPresent(String.self, forKey: .lastDomain)
            ?? URL(string: Self.defaultURL)?.host
            ?? "wkdomains.com"
        openTabs = try container.decodeIfPresent([String].self, forKey: .openTabs) ?? []
        openTabPins = try container.decodeIfPresent([Bool].self, forKey: .openTabPins) ?? []
        activeTabIndex = try container.decodeIfPresent(Int.self, forKey: .activeTabIndex) ?? 0
        historyURLs = try container.decodeIfPresent([String].self, forKey: .historyURLs) ?? []
        dark = try container.decodeIfPresent(Bool.self, forKey: .dark) ?? true
        darkDisabledSites = try container.decodeIfPresent([String].self, forKey: .darkDisabledSites) ?? []
        siteIdentities = try container.decodeIfPresent([String: [SiteIdentity]].self, forKey: .siteIdentities) ?? [:]
        activeSiteIdentityIDs = try container.decodeIfPresent([String: UUID].self, forKey: .activeSiteIdentityIDs) ?? [:]
    }
}

final class AppSettingsStore {
    static let shared = AppSettingsStore()

    let directoryURL: URL
    let settingsURL: URL

    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private var cachedSettings: AppSettings

    init(fileManager: FileManager = .default) {
        directoryURL = Self.realHomeDirectoryURL(fileManager: fileManager)
            .appendingPathComponent(".config/wkdomains", isDirectory: true)
        settingsURL = directoryURL.appendingPathComponent("settings.json")

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601

        cachedSettings = Self.readSettings(from: settingsURL, decoder: decoder)
            ?? Self.readSettings(
                from: fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent(".config/wkdomains/settings.json"),
                decoder: decoder
            )
            ?? .defaults
        write(cachedSettings)
    }

    var settings: AppSettings {
        cachedSettings
    }

    var startupURL: URL {
        Self.validURL(from: cachedSettings.lastURL) ?? URL(string: AppSettings.defaultURL)!
    }

    var startupURLs: [URL] {
        let urls = cachedSettings.openTabs.compactMap(Self.validURL)
        return urls.isEmpty ? [startupURL] : urls
    }

    var startupTabPins: [Bool] {
        let urls = cachedSettings.openTabs.compactMap(Self.validURL)
        guard !urls.isEmpty else { return [false] }

        return urls.indices.map { index in
            cachedSettings.openTabPins.indices.contains(index) ? cachedSettings.openTabPins[index] : false
        }
    }

    var startupActiveTabIndex: Int {
        guard startupURLs.indices.contains(cachedSettings.activeTabIndex) else { return 0 }
        return cachedSettings.activeTabIndex
    }

    var darkDisabledSites: [String] {
        cachedSettings.darkDisabledSites
    }

    var bookmarkURLs: [URL] {
        cachedSettings.bookmarks.compactMap(Self.validURL)
    }

    var isGlobalDarkModeEnabled: Bool {
        cachedSettings.dark
    }

    func usesDarkMode(for url: URL?) -> Bool {
        cachedSettings.dark && !isDarkModeDisabled(for: url)
    }

    func isDarkModeDisabled(for url: URL?) -> Bool {
        guard let host = url.flatMap(Self.normalizedHost(for:)) else { return false }
        return Set(cachedSettings.darkDisabledSites).contains(host)
    }

    func toggleDarkModeDisabled(for url: URL) {
        guard let host = Self.normalizedHost(for: url) else { return }

        var disabledSites = Set(cachedSettings.darkDisabledSites)
        if disabledSites.contains(host) {
            disabledSites.remove(host)
        } else {
            disabledSites.insert(host)
        }

        cachedSettings.darkDisabledSites = disabledSites.sorted()
        write(cachedSettings)
    }

    func isBookmarked(_ url: URL?) -> Bool {
        guard let url,
              let normalizedURL = Self.validURL(from: url.absoluteString)
        else {
            return false
        }

        return Set(cachedSettings.bookmarks).contains(normalizedURL.absoluteString)
    }

    func toggleBookmark(for url: URL) {
        guard let normalizedURL = Self.validURL(from: url.absoluteString) else { return }

        let normalizedURLString = normalizedURL.absoluteString
        if let index = cachedSettings.bookmarks.firstIndex(of: normalizedURLString) {
            cachedSettings.bookmarks.remove(at: index)
        } else {
            cachedSettings.bookmarks.append(normalizedURLString)
        }

        cachedSettings.bookmarks = Self.normalizedBookmarkURLs(cachedSettings.bookmarks)
        write(cachedSettings)
    }

    func moveBookmark(_ sourceURL: URL, to targetURL: URL) {
        guard let sourceURL = Self.validURL(from: sourceURL.absoluteString),
              let targetURL = Self.validURL(from: targetURL.absoluteString)
        else {
            return
        }

        var bookmarks = Self.normalizedBookmarkURLs(cachedSettings.bookmarks)
        guard let sourceIndex = bookmarks.firstIndex(of: sourceURL.absoluteString),
              let targetIndex = bookmarks.firstIndex(of: targetURL.absoluteString),
              sourceIndex != targetIndex
        else {
            return
        }

        let movedBookmark = bookmarks.remove(at: sourceIndex)
        bookmarks.insert(movedBookmark, at: targetIndex)
        cachedSettings.bookmarks = bookmarks
        write(cachedSettings)
    }

    func activeIdentityID(for url: URL) -> UUID? {
        guard let siteKey = Self.siteKey(for: url),
              let identityID = cachedSettings.activeSiteIdentityIDs[siteKey],
              identity(withID: identityID, forSiteKey: siteKey) != nil
        else {
            return nil
        }

        return identityID
    }

    func siteIdentityMenuItems(for url: URL?, activeIdentityID: UUID?) -> [BrowserSiteIdentityMenuItem] {
        guard let siteKey = url.flatMap(Self.siteKey(for:)) else {
            return [
                BrowserSiteIdentityMenuItem(
                    id: BrowserSiteIdentityMenuItem.defaultID,
                    title: "Default",
                    isCurrent: activeIdentityID == nil
                )
            ]
        }

        let identities = cachedSettings.siteIdentities[siteKey] ?? []
        return [
            BrowserSiteIdentityMenuItem(
                id: BrowserSiteIdentityMenuItem.defaultID,
                title: "Default",
                isCurrent: activeIdentityID == nil
            )
        ] + identities.map { identity in
            BrowserSiteIdentityMenuItem(
                id: identity.id.uuidString,
                title: identity.name,
                isCurrent: identity.id == activeIdentityID
            )
        }
    }

    func identityName(for identityID: UUID?) -> String {
        guard let identityID,
              let identity = identity(withID: identityID)
        else {
            return "Default"
        }

        return identity.name
    }

    func createIdentity(for url: URL) -> SiteIdentity? {
        guard let siteKey = Self.siteKey(for: url),
              let normalizedURL = Self.validURL(from: url.absoluteString)
        else {
            return nil
        }

        var identities = cachedSettings.siteIdentities[siteKey] ?? []
        let now = Date()
        let identity = SiteIdentity(
            id: UUID(),
            siteKey: siteKey,
            name: nextIdentityName(for: identities),
            lastURL: normalizedURL.absoluteString,
            createdAt: now,
            lastUsedAt: now
        )

        identities.append(identity)
        cachedSettings.siteIdentities[siteKey] = identities
        cachedSettings.activeSiteIdentityIDs[siteKey] = identity.id
        write(cachedSettings)
        return identity
    }

    func setActiveIdentity(_ identityID: UUID?, for url: URL) {
        guard let siteKey = Self.siteKey(for: url) else { return }

        if let identityID,
           updateIdentity(withID: identityID, forSiteKey: siteKey, lastURL: url.absoluteString, lastUsedAt: Date())
        {
            cachedSettings.activeSiteIdentityIDs[siteKey] = identityID
        } else {
            cachedSettings.activeSiteIdentityIDs.removeValue(forKey: siteKey)
        }

        write(cachedSettings)
    }

    func updateLastVisitedURL(_ url: URL, identityID: UUID?) {
        guard let normalizedURL = Self.validURL(from: url.absoluteString),
              let host = normalizedURL.host
        else {
            return
        }

        let normalizedURLString = normalizedURL.absoluteString
        let history = Self.historyByPrepending(normalizedURLString, to: cachedSettings.historyURLs)
        let identityChanged = updateIdentityForVisitedURL(normalizedURL, identityID: identityID)
        let hasChanged = cachedSettings.lastURL != normalizedURLString
            || cachedSettings.lastDomain != host
            || cachedSettings.historyURLs != history
            || identityChanged

        guard hasChanged else { return }

        cachedSettings.lastURL = normalizedURL.absoluteString
        cachedSettings.lastDomain = host
        cachedSettings.historyURLs = history
        write(cachedSettings)
    }

    func updateOpenTabs(_ rawURLs: [String], activeIndex: Int, pinnedFlags: [Bool]) {
        let normalizedTabs = Self.normalizedOpenTabs(rawURLs, pinnedFlags: pinnedFlags)
        let nextURLs = normalizedTabs.urls.isEmpty ? [cachedSettings.lastURL] : normalizedTabs.urls
        let nextPins = normalizedTabs.urls.isEmpty ? [false] : normalizedTabs.pinnedFlags
        let nextActiveIndex = nextURLs.indices.contains(activeIndex) ? activeIndex : 0

        guard cachedSettings.openTabs != nextURLs
            || cachedSettings.openTabPins != nextPins
            || cachedSettings.activeTabIndex != nextActiveIndex
        else {
            return
        }

        cachedSettings.openTabs = nextURLs
        cachedSettings.openTabPins = nextPins
        cachedSettings.activeTabIndex = nextActiveIndex
        write(cachedSettings)
    }

    private func identity(withID identityID: UUID) -> SiteIdentity? {
        for identities in cachedSettings.siteIdentities.values {
            if let identity = identities.first(where: { $0.id == identityID }) {
                return identity
            }
        }

        return nil
    }

    private func identity(withID identityID: UUID, forSiteKey siteKey: String) -> SiteIdentity? {
        cachedSettings.siteIdentities[siteKey]?.first(where: { $0.id == identityID })
    }

    private func updateIdentityForVisitedURL(_ url: URL, identityID: UUID?) -> Bool {
        guard let identityID,
              let siteKey = Self.siteKey(for: url)
        else {
            return false
        }

        return updateIdentity(
            withID: identityID,
            forSiteKey: siteKey,
            lastURL: url.absoluteString,
            lastUsedAt: Date()
        )
    }

    @discardableResult
    private func updateIdentity(
        withID identityID: UUID,
        forSiteKey siteKey: String,
        lastURL: String?,
        lastUsedAt: Date
    ) -> Bool {
        guard var identities = cachedSettings.siteIdentities[siteKey],
              let index = identities.firstIndex(where: { $0.id == identityID })
        else {
            return false
        }

        if let lastURL,
           Self.validURL(from: lastURL) != nil
        {
            identities[index].lastURL = lastURL
        }

        identities[index].lastUsedAt = lastUsedAt
        cachedSettings.siteIdentities[siteKey] = identities
        return true
    }

    private func nextIdentityName(for identities: [SiteIdentity]) -> String {
        let existingNames = Set(identities.map { $0.name })
        var index = identities.count + 2

        while existingNames.contains("Account \(index)") {
            index += 1
        }

        return "Account \(index)"
    }

    nonisolated private static func validURL(from value: String) -> URL? {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil,
              let url = components.url
        else {
            return nil
        }

        return url
    }

    private static func historyByPrepending(_ urlString: String, to history: [String]) -> [String] {
        var seen = Set<String>()
        var urls: [String] = []

        for value in [urlString] + history {
            guard let url = validURL(from: value) else { continue }

            let normalizedURLString = url.absoluteString
            guard !seen.contains(normalizedURLString) else { continue }

            seen.insert(normalizedURLString)
            urls.append(normalizedURLString)

            if urls.count == AppSettings.maxHistoryCount {
                break
            }
        }

        return urls
    }

    nonisolated private static func siteKey(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        return siteKey(forHost: host)
    }

    nonisolated private static func siteKey(forHost host: String) -> String {
        DomainUtilities.registrableDomain(from: host)
    }

    private func write(_ settings: AppSettings) {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            let data = try encoder.encode(settings)
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            NSLog("Could not write settings: \(error.localizedDescription)")
        }
    }

    private static func readSettings(from url: URL, decoder: JSONDecoder) -> AppSettings? {
        guard let data = try? Data(contentsOf: url),
              var settings = try? decoder.decode(AppSettings.self, from: data)
        else {
            return nil
        }

        if settings.port == 0 {
            settings.port = AppSettings.defaultPort
        }

        if let lastURL = validURL(from: settings.lastURL),
           let host = lastURL.host
        {
            settings.lastURL = lastURL.absoluteString
            settings.lastDomain = host
        } else {
            let defaultURL = URL(string: AppSettings.defaultURL)!
            settings.lastURL = defaultURL.absoluteString
            settings.lastDomain = defaultURL.host ?? "wkdomains.com"
        }

        let normalizedTabs = normalizedOpenTabs(settings.openTabs, pinnedFlags: settings.openTabPins)
        settings.openTabs = normalizedTabs.urls
        settings.openTabPins = normalizedTabs.pinnedFlags
        if settings.openTabs.isEmpty {
            settings.openTabs = [settings.lastURL]
            settings.openTabPins = [false]
        }
        if !settings.openTabs.indices.contains(settings.activeTabIndex) {
            settings.activeTabIndex = 0
        }

        settings.historyURLs = historyByPrepending(settings.lastURL, to: settings.historyURLs)
        settings.bookmarks = normalizedBookmarkURLs(settings.bookmarks)
        settings.darkDisabledSites = normalizedHosts(settings.darkDisabledSites)
        settings.siteIdentities = normalizedSiteIdentities(settings.siteIdentities)
        settings.activeSiteIdentityIDs = settings.activeSiteIdentityIDs.filter { siteKey, identityID in
            settings.siteIdentities[siteKey]?.contains(where: { $0.id == identityID }) == true
        }
        return settings
    }

    nonisolated private static func normalizedBookmarkURLs(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var urls: [String] = []

        for value in values {
            guard let url = validURL(from: value) else { continue }

            let normalizedURLString = url.absoluteString
            guard seen.insert(normalizedURLString).inserted else { continue }
            urls.append(normalizedURLString)
        }

        return urls
    }

    nonisolated private static func normalizedOpenTabURLs(_ values: [String]) -> [String] {
        values.compactMap { value in
            validURL(from: value)?.absoluteString
        }
    }

    nonisolated private static func normalizedOpenTabs(
        _ values: [String],
        pinnedFlags: [Bool]
    ) -> (urls: [String], pinnedFlags: [Bool]) {
        var urls: [String] = []
        var normalizedPinnedFlags: [Bool] = []

        for (index, value) in values.enumerated() {
            guard let url = validURL(from: value) else { continue }

            urls.append(url.absoluteString)
            normalizedPinnedFlags.append(pinnedFlags.indices.contains(index) ? pinnedFlags[index] : false)
        }

        return (urls, normalizedPinnedFlags)
    }

    nonisolated private static func normalizedHosts(_ values: [String]) -> [String] {
        Array(Set(values.compactMap(normalizedHost))).sorted()
    }

    nonisolated private static func normalizedHost(from value: String) -> String? {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let host = url.host
        {
            return normalizedHost(host)
        }

        if trimmed.hasPrefix("*.") {
            trimmed.removeFirst(2)
        }

        if let slashIndex = trimmed.firstIndex(of: "/") {
            trimmed = String(trimmed[..<slashIndex])
        }

        if let colonIndex = trimmed.firstIndex(of: ":") {
            trimmed = String(trimmed[..<colonIndex])
        }

        trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !trimmed.isEmpty else { return nil }
        return normalizedHost(trimmed)
    }

    nonisolated private static func normalizedHost(for url: URL) -> String? {
        guard let host = url.host else { return nil }
        return normalizedHost(host)
    }

    nonisolated private static func normalizedHost(_ host: String) -> String {
        host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func normalizedSiteIdentities(_ identitiesBySite: [String: [SiteIdentity]]) -> [String: [SiteIdentity]] {
        var normalized: [String: [SiteIdentity]] = [:]

        for (siteKey, identities) in identitiesBySite {
            let normalizedSiteKey = DomainUtilities.registrableDomain(from: siteKey)
            var seen = Set<UUID>()
            let validIdentities = identities.compactMap { identity -> SiteIdentity? in
                guard seen.insert(identity.id).inserted else { return nil }

                var identity = identity
                identity.siteKey = normalizedSiteKey
                identity.name = identity.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if identity.name.isEmpty {
                    identity.name = "Account \(seen.count + 1)"
                }
                if let lastURL = identity.lastURL,
                   validURL(from: lastURL) == nil
                {
                    identity.lastURL = nil
                }
                return identity
            }

            if !validIdentities.isEmpty {
                normalized[normalizedSiteKey] = validIdentities
            }
        }

        return normalized
    }

    private static func realHomeDirectoryURL(fileManager: FileManager) -> URL {
        guard let passwd = getpwuid(getuid()),
              let homePath = passwd.pointee.pw_dir
        else {
            return fileManager.homeDirectoryForCurrentUser
        }

        return URL(fileURLWithPath: String(cString: homePath), isDirectory: true)
    }
}
