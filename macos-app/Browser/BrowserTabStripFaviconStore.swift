//
//  BrowserTabStripFaviconStore.swift
//  macos-app
//

import AppKit
import Combine
import Foundation

@MainActor
final class BrowserTabStripFaviconStore: ObservableObject {
    @Published private var images: [String: NSImage] = [:]
    private var requestedURLs = Set<String>()
    private var failedURLs = Set<String>()
    private static let cacheLifetime: TimeInterval = 24 * 60 * 60

    init() {
        Self.createCacheDirectoryIfNeeded()
    }

    func image(for url: URL?) -> NSImage? {
        guard let url else { return nil }

        let key = Self.domainKey(for: url)
        if images[key] == nil {
            if let cachedImage = Self.cachedImage(for: key) {
                images[key] = cachedImage
                return cachedImage
            }

            requestImage(for: url, cacheKey: key)
        }

        return images[key]
    }

    private func requestImage(for url: URL, cacheKey: String) {
        guard !failedURLs.contains(cacheKey),
              requestedURLs.insert(cacheKey).inserted
        else {
            return
        }

        Task {
            for faviconURL in Self.faviconURLs(for: url) {
                guard let data = try? await Self.fetchData(from: faviconURL),
                      let image = Self.image(from: data)
                else {
                    continue
                }

                Self.writeCachedData(data, for: cacheKey)
                images[cacheKey] = image
                return
            }

            failedURLs.insert(cacheKey)
        }
    }

    private static func domainKey(for url: URL) -> String {
        url.host?.lowercased() ?? url.absoluteString.lowercased()
    }

    private static func cachedImage(for cacheKey: String) -> NSImage? {
        let fileURL = cacheFileURL(for: cacheKey)
        guard isFreshCacheFile(at: fileURL),
              let data = try? Data(contentsOf: fileURL)
        else {
            return nil
        }

        return image(from: data)
    }

    private static func writeCachedData(_ data: Data, for cacheKey: String) {
        let fileURL = cacheFileURL(for: cacheKey)
        do {
            try ensureCacheDirectoryExists()
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Could not cache favicon for \(cacheKey): \(error.localizedDescription)")
        }
    }

    private static func ensureCacheDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: cacheDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private static func createCacheDirectoryIfNeeded() {
        do {
            try ensureCacheDirectoryExists()
        } catch {
            NSLog("Could not create favicon cache directory: \(error.localizedDescription)")
        }
    }

    private static func isFreshCacheFile(at fileURL: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modificationDate = attributes[.modificationDate] as? Date
        else {
            return false
        }

        return Date().timeIntervalSince(modificationDate) < cacheLifetime
    }

    private static var cacheDirectoryURL: URL {
        realHomeDirectoryURL(fileManager: .default)
            .appendingPathComponent(".cache/wkdomains/favicons", isDirectory: true)
    }

    private static func realHomeDirectoryURL(fileManager: FileManager) -> URL {
        guard let passwd = getpwuid(getuid()),
              let homePath = passwd.pointee.pw_dir
        else {
            return fileManager.homeDirectoryForCurrentUser
        }

        return URL(fileURLWithPath: String(cString: homePath), isDirectory: true)
    }

    private static func cacheFileURL(for cacheKey: String) -> URL {
        cacheDirectoryURL.appendingPathComponent("\(safeCacheFileName(for: cacheKey)).favicon")
    }

    private static func safeCacheFileName(for value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }
        return String(scalars.joined()).trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func faviconURLs(for url: URL) -> [URL] {
        [rootFaviconURL(for: url), googleFaviconURL(for: url)].compactMap { $0 }
    }

    private static func rootFaviconURL(for url: URL) -> URL? {
        guard let scheme = url.scheme,
              let host = url.host
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        components.path = "/favicon.ico"
        return components.url
    }

    private static func googleFaviconURL(for url: URL) -> URL? {
        guard var components = URLComponents(string: "https://www.google.com/s2/favicons") else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "domain_url", value: url.absoluteString),
            URLQueryItem(name: "sz", value: "32")
        ]

        return components.url
    }

    private static func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)

        if let response = response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            throw URLError(.badServerResponse)
        }

        return data
    }

    private static func image(from data: Data) -> NSImage? {
        guard let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}
