//
//  AddressResolver.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import Foundation

struct AddressResolution {
    enum Kind {
        case webpage
        case search
    }

    let kind: Kind
    let primaryURL: URL
    let fallbackURLs: [URL]
    let displayTitle: String
    let searchQuery: String?
    let didAppendDotCom: Bool
}

enum AddressResolver {
    static func resolve(_ rawValue: String) -> AddressResolution? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if hasExplicitScheme(value) {
            return explicitWebpageResolution(for: value)
        }

        if value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return searchResolution(for: value)
        }

        if isBareSearchKeyword(value) {
            return searchResolution(for: value)
        }

        return inferredWebpageResolution(for: value) ?? searchResolution(for: value)
    }

    static func searchURL(for query: String) -> URL? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

        var components = URLComponents(string: "https://duckduckgo.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmedQuery)
        ]

        return components?.url
    }

    static func displayText(for url: URL) -> String {
        guard let host = url.host else { return url.absoluteString }

        let path = url.path.isEmpty || url.path == "/" ? "" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        let fragment = url.fragment.map { "#\($0)" } ?? ""

        return "\(host)\(path)\(query)\(fragment)"
    }

    private static func explicitWebpageResolution(for value: String) -> AddressResolution? {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              hostLooksNavigable(host),
              let url = components.url
        else {
            return nil
        }

        return AddressResolution(
            kind: .webpage,
            primaryURL: url,
            fallbackURLs: [],
            displayTitle: displayText(for: url),
            searchQuery: nil,
            didAppendDotCom: false
        )
    }

    private static func inferredWebpageResolution(for value: String) -> AddressResolution? {
        guard !value.contains("@") else { return nil }

        let initialScheme = isLocalHostLike(value) ? "http" : "https"
        guard let components = URLComponents(string: "\(initialScheme)://\(value)"),
              let parsedHost = components.host
        else {
            return nil
        }

        let host = parsedHost

        guard hostLooksNavigable(host),
              let primaryURL = components.url
        else {
            return nil
        }

        return AddressResolution(
            kind: .webpage,
            primaryURL: primaryURL,
            fallbackURLs: fallbackURLs(for: components, primaryURL: primaryURL),
            displayTitle: displayText(for: primaryURL),
            searchQuery: nil,
            didAppendDotCom: false
        )
    }

    private static func searchResolution(for value: String) -> AddressResolution? {
        guard let url = searchURL(for: value) else { return nil }

        return AddressResolution(
            kind: .search,
            primaryURL: url,
            fallbackURLs: [],
            displayTitle: value,
            searchQuery: value,
            didAppendDotCom: false
        )
    }

    private static func fallbackURLs(for components: URLComponents, primaryURL: URL) -> [URL] {
        guard components.scheme == "https",
              let host = components.host,
              !isLocalHost(host),
              !isIPAddress(host)
        else {
            return []
        }

        var urls: [URL] = []
        let hosts = host.hasPrefix("www.") ? [host] : [host, "www.\(host)"]

        for scheme in ["https", "http"] {
            for candidateHost in hosts {
                var fallbackComponents = components
                fallbackComponents.scheme = scheme
                fallbackComponents.host = candidateHost

                guard let url = fallbackComponents.url,
                      url != primaryURL,
                      !urls.contains(url)
                else {
                    continue
                }

                urls.append(url)
            }
        }

        return urls
    }

    private static func hasExplicitScheme(_ value: String) -> Bool {
        value.range(of: "://") != nil
    }

    private static func isBareSearchKeyword(_ value: String) -> Bool {
        guard value.range(
            of: "^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$",
            options: .regularExpression
        ) != nil else {
            return false
        }

        return !isLocalHost(value) && !isIPAddress(value)
    }

    private static func hostLooksNavigable(_ host: String) -> Bool {
        if isLocalHost(host) || isIPAddress(host) {
            return true
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else { return false }

        return labels.allSatisfy { label in
            label.range(
                of: "^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$",
                options: .regularExpression
            ) != nil
        }
    }

    private static func isLocalHostLike(_ value: String) -> Bool {
        guard let components = URLComponents(string: "http://\(value)"),
              let host = components.host
        else {
            return false
        }

        return isLocalHost(host) || isLoopbackIPAddress(host)
    }

    private static func isLocalHost(_ host: String) -> Bool {
        let normalizedHost = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalizedHost == "localhost"
    }

    private static func isIPAddress(_ host: String) -> Bool {
        isIPv4Address(host) || host.contains(":")
    }

    private static func isLoopbackIPAddress(_ host: String) -> Bool {
        host == "::1" || host.hasPrefix("127.")
    }

    private static func isIPv4Address(_ host: String) -> Bool {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }

        return octets.allSatisfy { octet in
            guard !octet.isEmpty,
                  octet.allSatisfy({ $0.isNumber }),
                  let value = Int(octet),
                  (0...255).contains(value)
            else {
                return false
            }

            return true
        }
    }
}
