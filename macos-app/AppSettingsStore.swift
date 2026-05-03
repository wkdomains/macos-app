//
//  AppSettingsStore.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import Darwin
import Foundation

struct AppSettings: Codable {
    static let defaultPort: UInt16 = 9001
    static let defaultURL = "https://wkdomains.com"
    static let maxHistoryCount = 30

    var port: UInt16
    var lastURL: String
    var lastDomain: String
    var historyURLs: [String]

    static var defaults: AppSettings {
        AppSettings(
            port: defaultPort,
            lastURL: defaultURL,
            lastDomain: URL(string: defaultURL)?.host ?? "wkdomains.com",
            historyURLs: [defaultURL]
        )
    }

    init(port: UInt16, lastURL: String, lastDomain: String, historyURLs: [String]) {
        self.port = port
        self.lastURL = lastURL
        self.lastDomain = lastDomain
        self.historyURLs = historyURLs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        port = try container.decodeIfPresent(UInt16.self, forKey: .port) ?? Self.defaultPort
        lastURL = try container.decodeIfPresent(String.self, forKey: .lastURL) ?? Self.defaultURL
        lastDomain = try container.decodeIfPresent(String.self, forKey: .lastDomain)
            ?? URL(string: Self.defaultURL)?.host
            ?? "wkdomains.com"
        historyURLs = try container.decodeIfPresent([String].self, forKey: .historyURLs) ?? []
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
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

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

    func updateLastVisitedURL(_ url: URL) {
        guard let normalizedURL = Self.validURL(from: url.absoluteString),
              let host = normalizedURL.host
        else {
            return
        }

        let normalizedURLString = normalizedURL.absoluteString
        let history = Self.historyByPrepending(normalizedURLString, to: cachedSettings.historyURLs)
        let hasChanged = cachedSettings.lastURL != normalizedURLString
            || cachedSettings.lastDomain != host
            || cachedSettings.historyURLs != history

        guard hasChanged else { return }

        cachedSettings.lastURL = normalizedURL.absoluteString
        cachedSettings.lastDomain = host
        cachedSettings.historyURLs = history
        write(cachedSettings)
    }

    private static func validURL(from value: String) -> URL? {
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

        settings.historyURLs = historyByPrepending(settings.lastURL, to: settings.historyURLs)
        return settings
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
