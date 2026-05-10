//
//  LocalAPIWebsiteDataReader+Storage.swift
//  macos-app
//

import Foundation
@preconcurrency import WebKit

extension WebsiteDataReader {
    func readStorage(for domain: RequestedDomain, completion: @escaping (DomainStorageResponse) -> Void) {
        let dataStore = browser.webView.configuration.websiteDataStore
        dataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self else { return }

                let matchingCookies = cookies
                    .filter { Self.cookie($0, matches: domain.host) }
                    .map(CookieResponse.init(cookie:))
                    .sorted { left, right in
                        if left.domain == right.domain {
                            return left.name < right.name
                        }

                        return left.domain < right.domain
                    }

                var localStorageReader: LocalStorageReader?
                localStorageReader = LocalStorageReader(dataStore: dataStore)
                localStorageReader?.readLocalStorage(for: domain.localStorageOrigins) { localStorageOrigins in
                    _ = localStorageReader
                    self.readActiveSessionStorage(for: domain) { sessionStorageOrigins in
                        completion(
                            DomainStorageResponse(
                                domain: domain.host,
                                cookies: matchingCookies,
                                localStorage: localStorageOrigins,
                                sessionStorage: sessionStorageOrigins
                            )
                        )
                    }
                }
            }
        }
    }

    func readStorageForCurrentPage(completion: @escaping (Result<DomainStorageResponse, Error>) -> Void) {
        do {
            let domain = try currentPageDomain()
            readStorage(for: domain) { response in
                completion(.success(response))
            }
        } catch {
            completion(.failure(error))
        }
    }

    func readCookieAuthShape(for domain: RequestedDomain, completion: @escaping ([String: Any]) -> Void) {
        let dataStore = browser.webView.configuration.websiteDataStore
        dataStore.httpCookieStore.getAllCookies { cookies in
            Task { @MainActor in
                let matchingCookies = cookies
                    .filter { Self.cookie($0, matches: domain.host) }
                    .sorted { left, right in
                        if left.domain == right.domain {
                            return left.name < right.name
                        }

                        return left.domain < right.domain
                    }

                completion([
                    "domain": domain.host,
                    "cookieCount": matchingCookies.count,
                    "cookies": matchingCookies.map(Self.safeCookieDictionary(from:)),
                    "note": "Cookie values are intentionally omitted from observe."
                ])
            }
        }
    }

    private func readCookieAuthShapeForCurrentPage(completion: @escaping ([String: Any]) -> Void) {
        guard let domain = try? currentPageDomain() else {
            completion([
                "cookieCount": 0,
                "cookies": [Any](),
                "note": "No page is loaded."
            ])
            return
        }

        readCookieAuthShape(for: domain, completion: completion)
    }

    private func readActiveSessionStorage(
        for domain: RequestedDomain,
        completion: @escaping ([SessionStorageOriginResponse]) -> Void
    ) {
        guard let url = browser.webView.url,
              let host = url.host?.lowercased(),
              domain.matches(host: host)
        else {
            completion([])
            return
        }

        let script = """
        JSON.stringify(Array.from({ length: sessionStorage.length }, (_, index) => {
            const key = sessionStorage.key(index);
            return { key, value: sessionStorage.getItem(key) };
        }))
        """

        browser.webView.evaluateJavaScript(script) { value, error in
            Task { @MainActor in
                let origin = Self.originString(from: url)

                if let error {
                    completion([
                        SessionStorageOriginResponse(
                            origin: origin,
                            items: [],
                            error: error.localizedDescription
                        )
                    ])
                    return
                }

                guard let json = value as? String,
                      let data = json.data(using: .utf8),
                      let items = try? JSONDecoder().decode([StorageItem].self, from: data)
                else {
                    completion([
                        SessionStorageOriginResponse(
                            origin: origin,
                            items: [],
                            error: "Could not decode sessionStorage."
                        )
                    ])
                    return
                }

                completion([
                    SessionStorageOriginResponse(
                        origin: origin,
                        items: items.sorted { $0.key < $1.key },
                        error: nil
                    )
                ])
            }
        }
    }

    static func cookieHeader(for url: URL, from cookies: [HTTPCookie]) -> String? {
        let matchingCookies = cookies.filter { cookie in
            Self.cookie(cookie, shouldBeSentTo: url)
        }

        guard !matchingCookies.isEmpty else {
            return nil
        }

        return matchingCookies
            .sorted { left, right in
                if left.path.count == right.path.count {
                    return left.name < right.name
                }

                return left.path.count > right.path.count
            }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    private static func safeCookieDictionary(from cookie: HTTPCookie) -> [String: Any] {
        [
            "name": cookie.name,
            "domain": cookie.domain,
            "path": cookie.path,
            "expiresAt": Self.json(cookie.expiresDate.map(Self.iso8601Formatter.string(from:))),
            "isSecure": cookie.isSecure,
            "isHTTPOnly": cookie.isHTTPOnly,
            "sameSitePolicy": Self.json(cookie.sameSitePolicy?.rawValue),
            "hasValue": !cookie.value.isEmpty
        ]
    }

    private static func cookie(_ cookie: HTTPCookie, matches host: String) -> Bool {
        let cookieDomain = cookie.domain
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return cookieDomain == host
            || cookieDomain.hasSuffix(".\(host)")
            || host.hasSuffix(".\(cookieDomain)")
    }

    private static func cookie(_ cookie: HTTPCookie, shouldBeSentTo url: URL) -> Bool {
        guard let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) else {
            return false
        }

        if cookie.isSecure, url.scheme?.lowercased() != "https" {
            return false
        }

        if let expiresDate = cookie.expiresDate, expiresDate <= Date() {
            return false
        }

        let requestPath = url.path.isEmpty ? "/" : url.path
        guard requestPath.hasPrefix(cookie.path) else {
            return false
        }

        return Self.cookie(cookie, matches: host)
    }
}
