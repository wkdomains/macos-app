//
//  BrowserCookiePersistence.swift
//  macos-app
//
//  Created by aa on 5/3/26.
//

import Foundation
import WebKit

final class BrowserCookiePersistence {
    private let directoryURL: URL
    private var profileID = "default"
    private var coordinator: ProfileCoordinator?

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func attach(to dataStore: WKWebsiteDataStore, identityID: UUID?, completion: @escaping () -> Void) {
        profileID = Self.profileID(for: identityID)
        BrowserSessionDiagnostics.log(
            "cookie attach requested profile=\(profileID)",
            directoryURL: directoryURL
        )

        let coordinator = Self.coordinator(for: profileID, directoryURL: directoryURL)
        self.coordinator = coordinator
        coordinator.attach(to: dataStore.httpCookieStore, completion: completion)
    }

    func saveNow() {
        coordinator?.saveNow()
    }

    static func saveAllProfileCookies(completion: (() -> Void)? = nil) {
        let coordinators = Array(profileCoordinators.values)
        guard !coordinators.isEmpty else {
            DispatchQueue.main.async {
                completion?()
            }
            return
        }   

        for coordinator in coordinators {
            coordinator.logSaveAllRequested(coordinatorCount: coordinators.count)
        }

        let group = DispatchGroup()
        for coordinator in coordinators {
            group.enter()
            coordinator.saveNow {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion?()
        }
    }

    func removePersistedCookies(matchingHost host: String) {
        (coordinator ?? Self.coordinator(for: profileID, directoryURL: directoryURL))
            .removePersistedCookies(matchingHost: host)
    }

    private static func coordinator(
        for profileID: String,
        directoryURL: URL
    ) -> ProfileCoordinator {
        let key = ProfileCoordinatorKey(directoryPath: directoryURL.path, profileID: profileID)
        if let coordinator = profileCoordinators[key] {
            return coordinator
        }

        let coordinator = ProfileCoordinator(directoryURL: directoryURL, profileID: profileID)
        profileCoordinators[key] = coordinator
        return coordinator
    }

    private struct ProfileCoordinatorKey: Hashable {
        var directoryPath: String
        var profileID: String
    }

    private static var profileCoordinators: [ProfileCoordinatorKey: ProfileCoordinator] = [:]

    private final class ProfileCoordinator: NSObject, WKHTTPCookieStoreObserver {
        private let directoryURL: URL
        private let profileID: String
        private var observedCookieStore: WKHTTPCookieStore?
        private var restoreCompletions: [() -> Void] = []
        private var hasRestored = false
        private var isRestoring = false
        private var saveTask: Task<Void, Never>?

        init(directoryURL: URL, profileID: String) {
            self.directoryURL = directoryURL
            self.profileID = profileID
            BrowserSessionDiagnostics.log(
                "cookie coordinator created profile=\(profileID)",
                directoryURL: directoryURL
            )
        }

        func logSaveAllRequested(coordinatorCount: Int) {
            BrowserSessionDiagnostics.log(
                "save all profiles requested coordinatorCount=\(coordinatorCount)",
                directoryURL: directoryURL
            )
        }

        func attach(to cookieStore: WKHTTPCookieStore, completion: @escaping () -> Void) {
            if observedCookieStore !== cookieStore {
                saveTask?.cancel()
                if let observedCookieStore {
                    BrowserSessionDiagnostics.log(
                        "cookie store replaced profile=\(profileID); saving previous store",
                        directoryURL: directoryURL
                    )
                    observedCookieStore.remove(self)
                    saveCookies(from: observedCookieStore)
                }

                observedCookieStore = cookieStore
                cookieStore.add(self)
                hasRestored = false
                isRestoring = false
                BrowserSessionDiagnostics.log(
                    "cookie store attached profile=\(profileID)",
                    directoryURL: directoryURL
                )
            }

            guard !hasRestored else {
                BrowserSessionDiagnostics.log(
                    "cookie restore skipped profile=\(profileID) reason=already-restored",
                    directoryURL: directoryURL
                )
                completion()
                return
            }

            restoreCompletions.append(completion)
            guard !isRestoring else {
                BrowserSessionDiagnostics.log(
                    "cookie restore queued profile=\(profileID) pendingCompletions=\(restoreCompletions.count)",
                    directoryURL: directoryURL
                )
                return
            }

            restoreCookies(into: cookieStore)
        }

        func saveNow(completion: (() -> Void)? = nil) {
            saveTask?.cancel()
            guard let observedCookieStore else {
                BrowserSessionDiagnostics.log(
                    "cookie save skipped profile=\(profileID) reason=no-observed-store",
                    directoryURL: directoryURL
                )
                completion?()
                return
            }

            BrowserSessionDiagnostics.log(
                "cookie save requested profile=\(profileID)",
                directoryURL: directoryURL
            )
            saveCookies(from: observedCookieStore, completion: completion)
        }

        func removePersistedCookies(matchingHost host: String) {
            saveTask?.cancel()

            let normalizedHost = BrowserCookiePersistence.normalizedHost(host)
            BrowserCookiePersistence.persistenceQueue.async { [directoryURL, profileID] in
                let archiveURLs = [
                    BrowserCookiePersistence.cookieArchiveURL(in: directoryURL, profileID: profileID),
                    BrowserCookiePersistence.cookieBackupArchiveURL(in: directoryURL, profileID: profileID)
                ]

                for archiveURL in archiveURLs {
                    let previousCookies = BrowserCookiePersistence.loadCookies(from: archiveURL)
                    let cookies = previousCookies.filter {
                        !BrowserCookiePersistence.cookie($0, matchesHost: normalizedHost)
                    }

                    do {
                        try BrowserCookiePersistence.writeCookies(cookies, to: archiveURL)
                        BrowserSessionDiagnostics.log(
                            """
                            cookie archive pruned profile=\(profileID) host=\(normalizedHost) \
                            file=\(archiveURL.lastPathComponent) before=\(previousCookies.count) after=\(cookies.count)
                            """,
                            directoryURL: directoryURL
                        )
                    } catch {
                        BrowserSessionDiagnostics.log(
                            "cookie archive prune failed profile=\(profileID) host=\(normalizedHost) file=\(archiveURL.lastPathComponent) error=\(error.localizedDescription)",
                            directoryURL: directoryURL
                        )
                        NSLog("Could not prune persisted browser cookies: \(error.localizedDescription)")
                    }
                }
            }
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            scheduleSave(from: cookieStore)
        }

        private func scheduleSave(from cookieStore: WKHTTPCookieStore) {
            guard !isRestoring else { return }

            saveTask?.cancel()
            saveTask = Task { [weak self, weak cookieStore] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled,
                      let self,
                      let cookieStore
                else {
                    return
                }

                self.saveCookies(from: cookieStore)
            }
        }

        private func saveCookies(
            from cookieStore: WKHTTPCookieStore,
            completion: (() -> Void)? = nil
        ) {
            let directoryURL = self.directoryURL
            let profileID = self.profileID
            cookieStore.getAllCookies { cookies in
                BrowserCookiePersistence.persistenceQueue.async {
                    do {
                        try FileManager.default.createDirectory(
                            at: directoryURL,
                            withIntermediateDirectories: true
                        )

                        let archiveURL = BrowserCookiePersistence.cookieArchiveURL(in: directoryURL, profileID: profileID)
                        let backupURL = BrowserCookiePersistence.cookieBackupArchiveURL(in: directoryURL, profileID: profileID)
                        let currentCookies = BrowserCookiePersistence.usableCookies(from: cookies)
                        let existingCookies = BrowserCookiePersistence.loadMergedCookies(primaryURL: archiveURL, backupURL: backupURL)
                        let shouldPreserveExisting = BrowserCookiePersistence.shouldPreserveExisting(
                            currentCookies,
                            preserving: existingCookies
                        )
                        let cookiesToWrite = shouldPreserveExisting
                            ? BrowserCookiePersistence.mergeCookies(currentCookies, preserving: existingCookies)
                            : currentCookies

                        if shouldPreserveExisting {
                            BrowserCookiePersistence.logPreservedCookieSnapshot(
                                profileID: profileID,
                                directoryURL: directoryURL,
                                currentCookies: currentCookies,
                                existingCookies: existingCookies
                            )
                        }

                        try BrowserCookiePersistence.backupArchiveIfNeeded(archiveURL: archiveURL, backupURL: backupURL)
                        try BrowserCookiePersistence.writeCookies(cookiesToWrite, to: archiveURL)
                        BrowserSessionDiagnostics.log(
                            """
                            cookie save completed profile=\(profileID) current=\(currentCookies.count) \
                            existing=\(existingCookies.count) written=\(cookiesToWrite.count) \
                            currentGoogleAuth=\(BrowserCookiePersistence.googleAuthCookieCount(in: currentCookies)) \
                            writtenGoogleAuth=\(BrowserCookiePersistence.googleAuthCookieCount(in: cookiesToWrite)) \
                            preserved=\(shouldPreserveExisting)
                            """,
                            directoryURL: directoryURL
                        )
                    } catch {
                        BrowserSessionDiagnostics.log(
                            "cookie save failed profile=\(profileID) error=\(error.localizedDescription)",
                            directoryURL: directoryURL
                        )
                        NSLog("Could not persist browser cookies: \(error.localizedDescription)")
                    }

                    DispatchQueue.main.async {
                        completion?()
                    }
                }
            }
        }

        private func restoreCookies(into cookieStore: WKHTTPCookieStore) {
            isRestoring = true

            let directoryURL = self.directoryURL
            let profileID = self.profileID
            BrowserCookiePersistence.persistenceQueue.async {
                let archiveURL = BrowserCookiePersistence.cookieArchiveURL(in: directoryURL, profileID: profileID)
                let backupURL = BrowserCookiePersistence.cookieBackupArchiveURL(in: directoryURL, profileID: profileID)
                let primaryCookies = BrowserCookiePersistence.loadCookies(from: archiveURL)
                let backupCookies = BrowserCookiePersistence.loadCookies(from: backupURL)
                let cookies = BrowserCookiePersistence.shouldPreserveExisting(
                    primaryCookies,
                    preserving: backupCookies
                )
                    ? BrowserCookiePersistence.mergeCookies(primaryCookies, preserving: backupCookies)
                    : primaryCookies

                BrowserSessionDiagnostics.log(
                    """
                    cookie restore loaded profile=\(profileID) primary=\(primaryCookies.count) \
                    backup=\(backupCookies.count) merged=\(cookies.count) \
                    mergedGoogleAuth=\(BrowserCookiePersistence.googleAuthCookieCount(in: cookies))
                    """,
                    directoryURL: directoryURL
                )

                DispatchQueue.main.async { [weak self, weak cookieStore] in
                    guard let self,
                          let cookieStore,
                          self.observedCookieStore === cookieStore
                    else {
                        return
                    }

                    self.restore(cookies, into: cookieStore)
                }
            }
        }

        private func restore(
            _ cookies: [HTTPCookie],
            into cookieStore: WKHTTPCookieStore
        ) {
            guard !cookies.isEmpty else {
                finishRestore(cookieStore: cookieStore)
                return
            }

            let group = DispatchGroup()

            for cookie in cookies {
                guard !cookie.isExpired else { continue }

                group.enter()
                cookieStore.setCookie(cookie) {
                    group.leave()
                }
            }

            group.notify(queue: .main) { [weak self, weak cookieStore] in
                guard let self,
                      let cookieStore
                else {
                    return
                }

                self.finishRestore(cookieStore: cookieStore)
            }
        }

        private func finishRestore(cookieStore: WKHTTPCookieStore) {
            isRestoring = false
            hasRestored = true

            let completions = restoreCompletions
            restoreCompletions.removeAll()

            BrowserSessionDiagnostics.log(
                "cookie restore finished profile=\(profileID) completionCount=\(completions.count)",
                directoryURL: directoryURL
            )
            scheduleSave(from: cookieStore)
            completions.forEach { $0() }
        }
    }

    nonisolated private static func loadMergedCookies(primaryURL: URL, backupURL: URL) -> [HTTPCookie] {
        let primaryCookies = loadCookies(from: primaryURL)
        let backupCookies = loadCookies(from: backupURL)

        guard shouldPreserveExisting(primaryCookies, preserving: backupCookies) else {
            return primaryCookies
        }

        return mergeCookies(primaryCookies, preserving: backupCookies)
    }

    nonisolated private static func loadCookies(from url: URL) -> [HTTPCookie] {
        guard let data = try? Data(contentsOf: url) else { return [] }

        if let records = try? PropertyListDecoder().decode([PersistentCookieRecord].self, from: data) {
            return usableCookies(from: records.compactMap(\.cookie))
        }

        if let legacyCookies = loadLegacyKeyedCookies(from: data), !legacyCookies.isEmpty {
            return usableCookies(from: legacyCookies)
        }

        let legacyPropertyListCookies = loadLegacyCookiePropertyList(from: data)
        if !legacyPropertyListCookies.isEmpty {
            return usableCookies(from: legacyPropertyListCookies)
        }

        return []
    }

    nonisolated private static func loadLegacyKeyedCookies(from data: Data) -> [HTTPCookie]? {
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            defer { unarchiver.finishDecoding() }
            return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? [HTTPCookie]
        } catch {
            return nil
        }
    }

    nonisolated private static func loadLegacyCookiePropertyList(from data: Data) -> [HTTPCookie] {
        guard let archive = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let objects = archive["$objects"] as? [Any],
              let top = archive["$top"] as? [String: Any],
              let root = legacyDictionary(for: top["root"], objects: objects),
              let cookieRefs = root["NS.objects"] as? [Any]
        else {
            return []
        }

        return cookieRefs.compactMap { cookieRef in
            guard let cookieObject = legacyDictionary(for: cookieRef, objects: objects),
                  let propertyObject = legacyDictionary(for: cookieObject["properties"], objects: objects),
                  let properties = legacyCookieProperties(from: propertyObject, objects: objects)
            else {
                return nil
            }

            return HTTPCookie(properties: properties)
        }
    }

    nonisolated private static func legacyCookieProperties(
        from object: [String: Any],
        objects: [Any]
    ) -> [HTTPCookiePropertyKey: Any]? {
        guard let keyRefs = object["NS.keys"] as? [Any],
              let valueRefs = object["NS.objects"] as? [Any]
        else {
            return nil
        }

        var properties: [HTTPCookiePropertyKey: Any] = [:]

        for (keyRef, valueRef) in zip(keyRefs, valueRefs) {
            guard let key = legacyObject(for: keyRef, objects: objects) as? String else { continue }

            let value = legacyCookieValue(for: valueRef, objects: objects)
            switch key {
            case HTTPCookiePropertyKey.domain.rawValue:
                properties[.domain] = stringValue(value)
            case HTTPCookiePropertyKey.path.rawValue:
                properties[.path] = stringValue(value)
            case HTTPCookiePropertyKey.name.rawValue:
                properties[.name] = stringValue(value)
            case HTTPCookiePropertyKey.value.rawValue:
                properties[.value] = stringValue(value)
            case HTTPCookiePropertyKey.version.rawValue:
                properties[.version] = stringValue(value) ?? "0"
            case HTTPCookiePropertyKey.expires.rawValue:
                properties[.expires] = dateValue(value)
            case HTTPCookiePropertyKey.secure.rawValue:
                if boolValue(value) {
                    properties[.secure] = "TRUE"
                }
            case httpOnlyPropertyKey.rawValue:
                if boolValue(value) {
                    properties[httpOnlyPropertyKey] = "TRUE"
                }
            case HTTPCookiePropertyKey.sameSitePolicy.rawValue:
                properties[.sameSitePolicy] = stringValue(value)
            default:
                break
            }
        }

        if properties[.path] == nil {
            properties[.path] = "/"
        }

        guard properties[.domain] != nil,
              properties[.name] != nil,
              properties[.value] != nil
        else {
            return nil
        }

        return properties
    }

    nonisolated private static func legacyCookieValue(for reference: Any?, objects: [Any]) -> Any? {
        guard let resolved = legacyObject(for: reference, objects: objects) else { return nil }

        if let dictionary = resolved as? [String: Any],
           let timeInterval = dictionary["NS.time"] as? Double {
            return Date(timeIntervalSinceReferenceDate: timeInterval)
        }

        return resolved
    }

    nonisolated private static func legacyDictionary(for reference: Any?, objects: [Any]) -> [String: Any]? {
        legacyObject(for: reference, objects: objects) as? [String: Any]
    }

    nonisolated private static func legacyObject(for reference: Any?, objects: [Any]) -> Any? {
        guard let reference else { return nil }

        if let index = legacyUIDValue(reference),
           objects.indices.contains(index) {
            return objects[index]
        }

        return reference
    }

    nonisolated private static func legacyUIDValue(_ reference: Any) -> Int? {
        let description = String(describing: reference)
        guard let range = description.range(of: "value = ") else { return nil }

        let digits = description[range.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    nonisolated private static func shouldPreserveExisting(
        _ currentCookies: [HTTPCookie],
        preserving existingCookies: [HTTPCookie]
    ) -> Bool {
        guard !existingCookies.isEmpty else { return false }
        guard !currentCookies.isEmpty else { return true }

        let currentKeys = Set(currentCookies.map(cookieKey))
        let existingKeys = Set(existingCookies.map(cookieKey))
        if existingKeys.count >= 20,
           currentKeys.count * 100 < existingKeys.count * 65 {
            return true
        }

        let currentGoogleAuthCount = googleAuthCookieCount(in: currentCookies)
        let existingGoogleAuthCount = googleAuthCookieCount(in: existingCookies)
        return existingGoogleAuthCount >= 2
            && currentGoogleAuthCount + 1 < existingGoogleAuthCount
    }

    nonisolated private static func mergeCookies(
        _ currentCookies: [HTTPCookie],
        preserving existingCookies: [HTTPCookie]
    ) -> [HTTPCookie] {
        var cookiesByKey: [CookieKey: HTTPCookie] = [:]

        for cookie in existingCookies {
            cookiesByKey[cookieKey(cookie)] = cookie
        }

        for cookie in currentCookies {
            cookiesByKey[cookieKey(cookie)] = cookie
        }

        return sortedCookies(Array(cookiesByKey.values))
    }

    nonisolated private static func sortedCookies(_ cookies: [HTTPCookie]) -> [HTTPCookie] {
        return cookies.sorted { lhs, rhs in
            let leftKey = cookieKey(lhs)
            let rightKey = cookieKey(rhs)
            return (leftKey.domain, leftKey.name, leftKey.path) < (rightKey.domain, rightKey.name, rightKey.path)
        }
    }

    nonisolated private static func backupArchiveIfNeeded(archiveURL: URL, backupURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: archiveURL.path) else { return }

        let archiveCookies = loadCookies(from: archiveURL)
        guard !archiveCookies.isEmpty else { return }

        let backupCookies = loadCookies(from: backupURL)
        guard backupCookies.isEmpty || archiveCookies.count >= backupCookies.count else { return }

        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }

        try fileManager.copyItem(at: archiveURL, to: backupURL)
    }

    nonisolated private static func writeCookies(_ cookies: [HTTPCookie], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let records = usableCookies(from: cookies).map(PersistentCookieRecord.init(cookie:))
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(records)
        try data.write(to: url, options: .atomic)
    }

    nonisolated private static func usableCookies(from cookies: [HTTPCookie]) -> [HTTPCookie] {
        var cookiesByKey: [CookieKey: HTTPCookie] = [:]

        for cookie in cookies where !cookie.isExpired {
            cookiesByKey[cookieKey(cookie)] = cookie
        }

        return sortedCookies(Array(cookiesByKey.values))
    }

    nonisolated private static func cookieKey(_ cookie: HTTPCookie) -> CookieKey {
        CookieKey(
            domain: normalizedHost(cookie.domain),
            path: cookie.path,
            name: cookie.name
        )
    }

    nonisolated private static func cookie(_ cookie: HTTPCookie, matchesHost host: String) -> Bool {
        let cookieDomain = normalizedHost(cookie.domain)
        return cookieDomain == host
            || cookieDomain.hasSuffix(".\(host)")
            || host.hasSuffix(".\(cookieDomain)")
    }

    nonisolated private static func normalizedHost(_ host: String) -> String {
        host
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    nonisolated private static func googleAuthCookieCount(in cookies: [HTTPCookie]) -> Int {
        cookies.filter { cookie in
            let domain = normalizedHost(cookie.domain)
            return domain == "google.com" || domain.hasSuffix(".google.com")
        }
        .filter { googleAuthCookieNames.contains($0.name) }
        .count
    }

    nonisolated private static func logPreservedCookieSnapshot(
        profileID: String,
        directoryURL: URL,
        currentCookies: [HTTPCookie],
        existingCookies: [HTTPCookie]
    ) {
        BrowserSessionDiagnostics.log(
            """
            cookie snapshot preserved profile=\(profileID) current=\(currentCookies.count) \
            existing=\(existingCookies.count) currentGoogleAuth=\(googleAuthCookieCount(in: currentCookies)) \
            existingGoogleAuth=\(googleAuthCookieCount(in: existingCookies))
            """,
            directoryURL: directoryURL
        )

        NSLog(
            """
            Browser cookie snapshot for profile \(profileID) looked partial; preserving archive cookies. \
            current=\(currentCookies.count), existing=\(existingCookies.count), \
            currentGoogleAuth=\(googleAuthCookieCount(in: currentCookies)), \
            existingGoogleAuth=\(googleAuthCookieCount(in: existingCookies))
            """
        )
    }

    nonisolated private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    nonisolated private static func boolValue(_ value: Any?) -> Bool {
        switch value {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            return ["1", "true", "yes"].contains(value.lowercased())
        default:
            return false
        }
    }

    nonisolated private static func dateValue(_ value: Any?) -> Date? {
        switch value {
        case let value as Date:
            return value
        case let value as NSNumber:
            return Date(timeIntervalSinceReferenceDate: value.doubleValue)
        default:
            return nil
        }
    }

    nonisolated private static let defaultProfileID = "default"
    nonisolated private static let httpOnlyPropertyKey = HTTPCookiePropertyKey("HttpOnly")
    nonisolated private static let persistenceQueue = DispatchQueue(label: "com.wkdomains.browser.cookie-persistence")
    nonisolated private static let googleAuthCookieNames: Set<String> = [
        "APISID",
        "HSID",
        "LSID",
        "OSID",
        "SAPISID",
        "SID",
        "SIDCC",
        "SSID",
        "__Host-1PLSID",
        "__Host-3PLSID",
        "__Secure-1PAPISID",
        "__Secure-1PSID",
        "__Secure-1PSIDCC",
        "__Secure-1PSIDTS",
        "__Secure-3PAPISID",
        "__Secure-3PSID",
        "__Secure-3PSIDCC",
        "__Secure-3PSIDTS",
        "__Secure-OSID"
    ]

    nonisolated private static func profileID(for identityID: UUID?) -> String {
        identityID?.uuidString.lowercased() ?? defaultProfileID
    }

    nonisolated private static func cookieArchiveURL(in directoryURL: URL, profileID: String) -> URL {
        directoryURL.appendingPathComponent("cookies-\(profileID).archive")
    }

    nonisolated private static func cookieBackupArchiveURL(in directoryURL: URL, profileID: String) -> URL {
        directoryURL.appendingPathComponent("cookies-\(profileID).backup.archive")
    }

    nonisolated private struct CookieKey: Hashable {
        var domain: String
        var path: String
        var name: String
    }

    nonisolated private struct PersistentCookieRecord: Codable {
        var domain: String
        var path: String
        var name: String
        var value: String
        var expiresDate: Date?
        var isSecure: Bool
        var isHTTPOnly: Bool
        var sameSitePolicy: String?
        var version: Int

        init(cookie: HTTPCookie) {
            domain = cookie.domain
            path = cookie.path
            name = cookie.name
            value = cookie.value
            expiresDate = cookie.expiresDate
            isSecure = cookie.isSecure
            isHTTPOnly = cookie.isHTTPOnly
            sameSitePolicy = cookie.sameSitePolicy?.rawValue
            version = cookie.version
        }

        var cookie: HTTPCookie? {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: domain,
                .path: path,
                .name: name,
                .value: value,
                .version: "\(version)"
            ]

            if let expiresDate {
                properties[.expires] = expiresDate
            }

            if isSecure {
                properties[.secure] = "TRUE"
            }

            if isHTTPOnly {
                properties[BrowserCookiePersistence.httpOnlyPropertyKey] = "TRUE"
            }

            if let sameSitePolicy {
                properties[.sameSitePolicy] = sameSitePolicy
            }

            return HTTPCookie(properties: properties)
        }
    }
}

private extension HTTPCookie {
    nonisolated var isExpired: Bool {
        guard let expiresDate else { return false }
        return expiresDate <= Date()
    }
}

enum BrowserSessionDiagnostics {
    nonisolated private static let queue = DispatchQueue(label: "com.wkdomains.browser.session-diagnostics")
    nonisolated private static let logFileName = "session.log"
    nonisolated private static let rotatedLogFileName = "session.log.1"
    nonisolated private static let maxLogFileBytes: UInt64 = 1_000_000

    nonisolated static func log(_ message: String, directoryURL: URL) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let sanitizedMessage = message
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
        let line = "\(timestamp) \(sanitizedMessage)\n"

        queue.async {
            append(line, directoryURL: directoryURL)
        }
    }

    nonisolated private static func append(_ line: String, directoryURL: URL) {
        let fileManager = FileManager.default
        let logURL = directoryURL.appendingPathComponent(logFileName)
        let rotatedLogURL = directoryURL.appendingPathComponent(rotatedLogFileName)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try rotateLogIfNeeded(logURL: logURL, rotatedLogURL: rotatedLogURL, incomingByteCount: UInt64(line.utf8.count))

            if !fileManager.fileExists(atPath: logURL.path) {
                fileManager.createFile(atPath: logURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            NSLog("Could not write browser session diagnostics: \(error.localizedDescription)")
        }
    }

    nonisolated private static func rotateLogIfNeeded(
        logURL: URL,
        rotatedLogURL: URL,
        incomingByteCount: UInt64
    ) throws {
        let fileManager = FileManager.default
        guard let fileSize = try? fileManager
            .attributesOfItem(atPath: logURL.path)[.size] as? UInt64,
            fileSize + incomingByteCount > maxLogFileBytes
        else {
            return
        }

        if fileManager.fileExists(atPath: rotatedLogURL.path) {
            try fileManager.removeItem(at: rotatedLogURL)
        }

        try fileManager.moveItem(at: logURL, to: rotatedLogURL)
    }
}
