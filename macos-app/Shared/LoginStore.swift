//
//  LoginStore.swift
//  macos-app
//
//  Created by aa on 5/3/26.
//

import Foundation

struct SavedLoginEntry: Codable, Equatable {
    var host: String
    var identityID: UUID?
    var origin: String?
    var username: String
    var password: String
    var usernameTarget: LoginFieldTarget
    var passwordTarget: LoginFieldTarget
    var createdAt: Date
    var updatedAt: Date
}

private struct SavedLoginFile: Codable {
    var version: Int
    var entries: [SavedLoginEntry]
}

private struct SavedLoginSiteFile: Codable {
    var version: Int
    var sites: [SavedLoginSite]
}

private struct SavedLoginSite: Codable, Equatable {
    var host: String
    var origin: String?
    var usernameTarget: LoginFieldTarget
    var passwordTarget: LoginFieldTarget
    var accounts: [SavedLoginAccount]
    var updatedAt: Date
}

private struct SavedLoginAccount: Codable, Equatable {
    var identityID: UUID?
    var username: String
    var password: String
    var createdAt: Date
    var updatedAt: Date
}

final class LoginStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private var sitesByHost: [String: SavedLoginSite]

    init(directoryURL: URL, fileManager: FileManager = .default) {
        fileURL = directoryURL.appendingPathComponent("logins.json")

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601

        sitesByHost = Self.readSites(from: fileURL, decoder: decoder)
        if !sitesByHost.isEmpty {
            write()
        }
    }

    func login(for url: URL?, identityID: UUID?) -> SavedLoginEntry? {
        guard let host = Self.normalizedHost(for: url) else { return nil }
        guard let site = sitesByHost[host] else {
            return nil
        }
        let requestedAccountKey = Self.identityKey(identityID)
        let account = site.accounts.first { Self.identityKey($0.identityID) == requestedAccountKey }
            ?? site.accounts.first { $0.identityID == nil }

        guard let account else { return nil }

        return SavedLoginEntry(
            host: site.host,
            identityID: account.identityID,
            origin: site.origin,
            username: account.username,
            password: account.password,
            usernameTarget: site.usernameTarget,
            passwordTarget: site.passwordTarget,
            createdAt: account.createdAt,
            updatedAt: account.updatedAt
        )
    }

    func hasLogin(for url: URL?, identityID: UUID?) -> Bool {
        login(for: url, identityID: identityID) != nil
    }

    func save(
        username: String,
        password: String,
        usernameTarget: LoginFieldTarget,
        passwordTarget: LoginFieldTarget,
        for url: URL,
        identityID: UUID?
    ) {
        guard let host = Self.normalizedHost(for: url) else { return }

        let now = Date()
        let origin = Self.originString(from: url)
        var site = sitesByHost[host]

        var accounts = site?.accounts ?? []
        let accountKey = Self.identityKey(identityID)
        let existingIndex = accounts.firstIndex { Self.identityKey($0.identityID) == accountKey }
        let existingAccount = existingIndex.map { accounts[$0] }
        let nextAccount = SavedLoginAccount(
            identityID: identityID,
            username: username,
            password: password,
            createdAt: existingAccount?.createdAt ?? now,
            updatedAt: now
        )

        if let existingIndex {
            accounts[existingIndex] = nextAccount
        } else {
            accounts.append(nextAccount)
        }

        accounts.sort { Self.identityKey($0.identityID) < Self.identityKey($1.identityID) }

        site = SavedLoginSite(
            host: host,
            origin: origin,
            usernameTarget: usernameTarget,
            passwordTarget: passwordTarget,
            accounts: accounts,
            updatedAt: now
        )
        sitesByHost[host] = site
        write()
    }

    private func write() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let sites = sitesByHost.values.sorted { $0.host < $1.host }
            let file = SavedLoginSiteFile(
                version: 3,
                sites: sites
            )
            let data = try encoder.encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Could not write saved logins: \(error.localizedDescription)")
        }
    }

    private static func readSites(from url: URL, decoder: JSONDecoder) -> [String: SavedLoginSite] {
        guard let data = try? Data(contentsOf: url) else {
            return [:]
        }

        if let file = try? decoder.decode(SavedLoginSiteFile.self, from: data) {
            return normalizedSites(file.sites)
        }

        guard let file = try? decoder.decode(SavedLoginFile.self, from: data) else {
            return [:]
        }

        return sites(fromLegacyEntries: file.entries)
    }

    private static func normalizedSites(_ sites: [SavedLoginSite]) -> [String: SavedLoginSite] {
        var sitesByHost: [String: SavedLoginSite] = [:]

        for site in sites {
            let host = normalizedHost(site.host)
            guard !host.isEmpty, !site.accounts.isEmpty else { continue }

            var site = site
            site.host = host
            site.accounts = site.accounts.sorted { identityKey($0.identityID) < identityKey($1.identityID) }
            sitesByHost[host] = site
        }

        return sitesByHost
    }

    private static func sites(fromLegacyEntries entries: [SavedLoginEntry]) -> [String: SavedLoginSite] {
        var sitesByHost: [String: SavedLoginSite] = [:]

        for entry in entries {
            let host = normalizedHost(entry.host)
            guard !host.isEmpty else { continue }

            var entry = entry
            entry.host = host

            let site = sitesByHost[host]
            var accounts = site?.accounts ?? []
            let accountKey = identityKey(entry.identityID)
            let account = SavedLoginAccount(
                identityID: entry.identityID,
                username: entry.username,
                password: entry.password,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt
            )

            if let existingIndex = accounts.firstIndex(where: { identityKey($0.identityID) == accountKey }) {
                accounts[existingIndex] = account
            } else {
                accounts.append(account)
            }

            accounts.sort { identityKey($0.identityID) < identityKey($1.identityID) }

            let shouldUseTargets = site == nil || entry.updatedAt >= (site?.updatedAt ?? .distantPast)
            sitesByHost[host] = SavedLoginSite(
                host: host,
                origin: entry.origin ?? site?.origin,
                usernameTarget: shouldUseTargets ? entry.usernameTarget : site!.usernameTarget,
                passwordTarget: shouldUseTargets ? entry.passwordTarget : site!.passwordTarget,
                accounts: accounts,
                updatedAt: max(entry.updatedAt, site?.updatedAt ?? .distantPast)
            )
        }

        return sitesByHost
    }

    private static func normalizedHost(for url: URL?) -> String? {
        guard let host = url?.host else { return nil }
        let normalized = normalizedHost(host)
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedHost(_ host: String) -> String {
        host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func identityKey(_ identityID: UUID?) -> String {
        identityID?.uuidString.lowercased() ?? "default"
    }

    private static func originString(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased()
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        return components.url?.absoluteString
    }
}
