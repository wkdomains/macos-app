//
//  LocalAPIWebsiteDataReader+Navigation.swift
//  macos-app
//

import Foundation
@preconcurrency import WebKit

extension WebsiteDataReader {
    func navigate(
        to rawURL: String,
        mode rawMode: String?,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let url = resolvedNavigationURL(from: rawURL) else {
            completion(.failure(InspectionError.invalidNavigationURL))
            return
        }

        let mode = rawMode?.lowercased() ?? "auto"

        switch mode {
        case "hard":
            hardNavigate(to: url, completion: completion)
        case "soft":
            softNavigate(to: url, fallbackToHard: false, completion: completion)
        case "auto":
            if currentOriginMatches(url) {
                softNavigate(to: url, fallbackToHard: true, completion: completion)
            } else {
                hardNavigate(to: url, completion: completion)
            }
        default:
            completion(.failure(InspectionError.invalidNavigationRequest))
        }
    }

    func readCurrentPage() -> [String: Any] {
        var response: [String: Any] = [:]

        if let url = browser.webView.url {
            response["url"] = url.absoluteString
            response["host"] = url.host
        }

        return response
    }

    func resolvedNavigationURL(from rawURL: String) -> URL? {
        let value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let url: URL?
        if let currentURL = browser.webView.url {
            url = URL(string: value, relativeTo: currentURL)?.absoluteURL
        } else {
            url = URL(string: value)
        }

        if let url,
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           url.host != nil {
            return url
        }

        if let resolution = AddressResolver.resolve(value) {
            return resolution.primaryURL
        }

        return nil
    }

    private func hardNavigate(to url: URL, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        let beforeURL = browser.webView.url?.absoluteString
        browser.load(url)
        let startedAt = Date()
        var didForceLoad = false

        func poll() {
            let elapsed = Date().timeIntervalSince(startedAt)
            let currentURL = self.browser.webView.url?.absoluteString
            let reachedURL = currentURL == url.absoluteString

            if !didForceLoad, currentURL == nil, !self.browser.webView.isLoading, elapsed >= 0.4 {
                didForceLoad = true
                BrowserDebugLogging.log("[wkdomains-debug] local-api navigate hard forcing direct webview load url=\(url.absoluteString)")
                self.browser.webView.load(URLRequest(url: url))
            }

            if reachedURL && (!self.browser.webView.isLoading || elapsed >= 1.0) {
                completion(
                    .success([
                        "ok": true,
                        "mode": "hard",
                        "requestedURL": url.absoluteString,
                        "beforeURL": Self.json(beforeURL),
                        "url": currentURL ?? url.absoluteString,
                        "forcedWebViewLoad": didForceLoad,
                        "elapsedMilliseconds": Int(elapsed * 1000)
                    ])
                )
                return
            }

            if elapsed >= 8 {
                completion(
                    .success([
                        "ok": false,
                        "mode": "hard",
                        "requestedURL": url.absoluteString,
                        "beforeURL": Self.json(beforeURL),
                        "url": Self.json(currentURL),
                        "forcedWebViewLoad": didForceLoad,
                        "timedOut": true,
                        "elapsedMilliseconds": Int(elapsed * 1000)
                    ])
                )
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                poll()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            poll()
        }
    }

    private func softNavigate(
        to url: URL,
        fallbackToHard: Bool,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard browser.webView.url != nil else {
            completion(.failure(InspectionError.noPageLoaded))
            return
        }

        guard currentOriginMatches(url) else {
            if fallbackToHard {
                hardNavigate(to: url, completion: completion)
            } else {
                completion(.failure(InspectionError.softNavigationRequiresSameOrigin))
            }
            return
        }

        guard let urlData = try? JSONEncoder().encode(url.absoluteString),
              let urlJSON = String(data: urlData, encoding: .utf8)
        else {
            completion(.failure(InspectionError.couldNotEncodeDiagnosticJSON))
            return
        }

        let script = """
        JSON.stringify((() => {
            const target = new URL(\(urlJSON), location.href);
            const beforeURL = location.href;
            const beforeHash = location.hash;

            if (target.origin !== location.origin) {
                return {
                    ok: false,
                    mode: "soft",
                    reason: "cross-origin",
                    requestedURL: target.href,
                    beforeURL,
                    url: location.href
                };
            }

            if (target.href !== location.href) {
                history.pushState(history.state, "", target.href);
                window.dispatchEvent(new PopStateEvent("popstate", { state: history.state }));

                if (beforeHash !== target.hash) {
                    window.dispatchEvent(new HashChangeEvent("hashchange", {
                        oldURL: beforeURL,
                        newURL: target.href
                    }));
                }
            }

            return {
                ok: true,
                mode: "soft",
                requestedURL: target.href,
                beforeURL,
                url: location.href,
                changed: beforeURL !== location.href
            };
        })())
        """

        evaluateJSONScript(script, label: "navigate-soft") { [weak self] result in
            switch result {
            case .success(let response):
                if let dictionary = response as? [String: Any],
                   dictionary["ok"] as? Bool == true {
                    completion(.success(dictionary))
                } else if fallbackToHard {
                    self?.hardNavigate(to: url, completion: completion)
                } else {
                    completion(.failure(InspectionError.softNavigationRequiresSameOrigin))
                }
            case .failure(let error):
                if fallbackToHard {
                    self?.hardNavigate(to: url, completion: completion)
                } else {
                    completion(.failure(error))
                }
            }
        }
    }

    private func currentOriginMatches(_ url: URL) -> Bool {
        guard let currentURL = browser.webView.url else { return false }
        return Self.originString(from: currentURL) == Self.originString(from: url)
    }
}
