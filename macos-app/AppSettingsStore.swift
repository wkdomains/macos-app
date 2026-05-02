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

    var port: UInt16
    var lastURL: String
    var lastDomain: String

    static var defaults: AppSettings {
        AppSettings(
            port: defaultPort,
            lastURL: defaultURL,
            lastDomain: URL(string: defaultURL)?.host ?? "wkdomains.com"
        )
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
        validURL(from: cachedSettings.lastURL) ?? URL(string: AppSettings.defaultURL)!
    }

    func updateLastVisitedURL(_ url: URL) {
        guard let normalizedURL = validURL(from: url.absoluteString),
              let host = normalizedURL.host,
              cachedSettings.lastURL != normalizedURL.absoluteString || cachedSettings.lastDomain != host
        else {
            return
        }

        cachedSettings.lastURL = normalizedURL.absoluteString
        cachedSettings.lastDomain = host
        write(cachedSettings)
    }

    private func validURL(from value: String) -> URL? {
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

        if URL(string: settings.lastURL)?.host == nil {
            settings.lastURL = AppSettings.defaultURL
            settings.lastDomain = URL(string: AppSettings.defaultURL)?.host ?? "wkdomains.com"
        }

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
