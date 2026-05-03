//
//  LoginStore.swift
//  macos-app
//
//  Created by aa on 5/3/26.
//

import Foundation

struct SavedLoginEntry: Codable, Equatable {
    var host: String
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

final class LoginStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private var entriesByHost: [String: SavedLoginEntry]

    init(directoryURL: URL, fileManager: FileManager = .default) {
        fileURL = directoryURL.appendingPathComponent("logins.json")

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601

        entriesByHost = Self.readEntries(from: fileURL, decoder: decoder)
        if !entriesByHost.isEmpty {
            write()
        }
    }

    func login(for url: URL?) -> SavedLoginEntry? {
        guard let host = Self.normalizedHost(for: url) else { return nil }
        return entriesByHost[host]
    }

    func hasLogin(for url: URL?) -> Bool {
        login(for: url) != nil
    }

    func save(
        username: String,
        password: String,
        usernameTarget: LoginFieldTarget,
        passwordTarget: LoginFieldTarget,
        for url: URL
    ) {
        guard let host = Self.normalizedHost(for: url) else { return }

        let now = Date()
        let existing = entriesByHost[host]
        let origin = Self.originString(from: url)

        entriesByHost[host] = SavedLoginEntry(
            host: host,
            origin: origin,
            username: username,
            password: password,
            usernameTarget: usernameTarget,
            passwordTarget: passwordTarget,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        write()
    }

    private func write() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let file = SavedLoginFile(
                version: 1,
                entries: entriesByHost.values.sorted { $0.host < $1.host }
            )
            let data = try encoder.encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Could not write saved logins: \(error.localizedDescription)")
        }
    }

    private static func readEntries(from url: URL, decoder: JSONDecoder) -> [String: SavedLoginEntry] {
        guard let data = try? Data(contentsOf: url),
              let file = try? decoder.decode(SavedLoginFile.self, from: data)
        else {
            return [:]
        }

        var entries: [String: SavedLoginEntry] = [:]
        for entry in file.entries {
            let host = normalizedHost(entry.host)
            guard !host.isEmpty else { continue }

            var entry = entry
            entry.host = host
            entries[host] = entry
        }
        return entries
    }

    private static func normalizedHost(for url: URL?) -> String? {
        guard let host = url?.host else { return nil }
        let normalized = normalizedHost(host)
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedHost(_ host: String) -> String {
        host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
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
