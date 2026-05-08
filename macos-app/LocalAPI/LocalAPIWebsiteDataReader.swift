//
//  LocalAPIWebsiteDataReader.swift
//  macos-app
//

import Foundation
@preconcurrency import WebKit

@MainActor
final class WebsiteDataReader {
    private let browser: BrowserModel

    init(browser: BrowserModel) {
        self.browser = browser
    }

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

    func readXHRRequests(for domain: RequestedDomain) -> XHRRequestsResponse {
        let requests = browser.sortedXHRRequests(for: domain.host)
            .map(XHRRequestResponse.init(record:))

        return XHRRequestsResponse(
            hostname: domain.host,
            activePageURL: browser.webView.url?.absoluteString,
            activePageHost: browser.webView.url?.host,
            requests: requests
        )
    }

    func readXHRRequestsForCurrentPage() -> Result<XHRRequestsResponse, Error> {
        do {
            return .success(readXHRRequests(for: try currentPageDomain()))
        } catch {
            return .failure(error)
        }
    }

    func replayXHRRequestForCurrentPage(
        at index: Int,
        completion: @escaping (Result<XHRReplayResponse, Error>) -> Void
    ) {
        do {
            let domain = try currentPageDomain()
            let requests = readXHRRequests(for: domain).requests

            guard requests.indices.contains(index) else {
                throw InspectionError.xhrIndexOutOfRange(index)
            }

            let xhr = requests[index]
            guard let url = URL(string: xhr.url) else {
                throw InspectionError.invalidXHRURL
            }

            let dataStore = browser.webView.configuration.websiteDataStore
            dataStore.httpCookieStore.getAllCookies { cookies in
                Task { @MainActor in
                    let cookieHeader = Self.cookieHeader(for: url, from: cookies)

                    do {
                        let response = try await Self.fetchXHRJSON(
                            xhr: xhr,
                            url: url,
                            cookieHeader: cookieHeader
                        )
                        completion(.success(response))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    func readScreenshot(completion: @escaping (Result<Data, Error>) -> Void) {
        browser.currentVisiblePageScreenshotPNG(completion: completion)
    }

    func readPage() -> PageResponse {
        let url = browser.webView.url
        let host = url?.host?.lowercased()
        let viewportWidth = browser.viewportMode.width ?? browser.webView.bounds.width

        return PageResponse(
            url: url?.absoluteString,
            title: browser.webView.title,
            host: host,
            domain: host.map(DomainUtilities.registrableDomain(from:)),
            origin: url.map(Self.originString(from:)),
            viewportMode: browser.viewportMode.rawValue,
            viewportWidth: Int(viewportWidth.rounded()),
            viewportHeight: Int(browser.webView.bounds.height.rounded()),
            isLoading: browser.webView.isLoading,
            canGoBack: browser.webView.canGoBack,
            canGoForward: browser.webView.canGoForward
        )
    }

    func readConsoleMessages() -> ConsoleMessagesResponse {
        let messages = browser.consoleMessages().map(ConsoleMessageResponse.init(record:))

        return ConsoleMessagesResponse(
            activePageURL: browser.webView.url?.absoluteString,
            activePageHost: browser.webView.url?.host,
            captureScope: "page JavaScript console calls, window errors, unhandled promise rejections, and CSP violations captured inside WKWebView; browser-engine DevTools diagnostics are not exposed by WKWebView",
            capturedLevels: ["debug", "error", "info", "log", "warn"],
            messages: messages
        )
    }

    func readDOM(completion: @escaping (Result<Any, Error>) -> Void) {
        evaluateJSONScript(BrowserModel.domInspectionScript, label: "dom", completion: completion)
    }

    func readLinks(completion: @escaping (Result<Any, Error>) -> Void) {
        evaluateJSONScript(BrowserModel.linksInspectionScript, label: "links", completion: completion)
    }

    func readResources(completion: @escaping (DomainResourcesResponse) -> Void) {
        guard let host = browser.webView.url?.host?.lowercased() else {
            completion(DomainResourcesResponse(domain: nil, pageHost: nil, resources: []))
            return
        }

        let domain = DomainUtilities.registrableDomain(from: host)
        let candidates = Self.resourceCandidates(for: domain)

        Task {
            var resources: [DomainResourceResponse] = []

            for candidate in candidates {
                resources.append(await Self.fetchResource(candidate))
            }

            completion(
                DomainResourcesResponse(
                    domain: domain,
                    pageHost: host,
                    resources: resources
                )
            )
        }
    }

    func readDarkModeStatus(completion: @escaping (Result<Any, Error>) -> Void) {
        guard browser.webView.url != nil else {
            completion(.failure(InspectionError.noPageLoaded))
            return
        }

        let script = """
        JSON.stringify((() => {
            const callStatus = (name) => {
                try {
                    const fn = window[name];
                    return typeof fn === "function" ? fn() : null;
                } catch (error) {
                    return { error: String(error && error.message || error) };
                }
            };

            return {
                url: location.href,
                title: document.title,
                readyState: document.readyState,
                pageWorldFlags: {
                    darkModeInstalled: !!window.__wkdomainsDarkModeInstalled,
                    pageProxyInstalled: !!window.__wkdomainsDarkModePageProxyInstalled
                },
                engine: callStatus("__wkdomainsDarkModeStatus"),
                pageProxy: callStatus("__wkdomainsDarkModePageProxyStatus")
            };
        })())
        """

        let startedAt = Date()
        BrowserDebugLogging.log("[wkdomains-debug] local-api dark-mode start \(pageStateDescription())")

        var pageWorldObject: Any?
        var defaultClientObject: Any?
        var darkModeWorldObject: Any?
        var pageWorldError: String?
        var defaultClientError: String?
        var darkModeWorldError: String?
        var pending = 3

        let decodeStatusObject = { (value: Any?) -> Any? in
            guard let json = value as? String,
                  let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data)
            else {
                return nil
            }

            return object
        }

        let finishIfReady = {
            pending -= 1
            guard pending == 0 else { return }

            var response: [String: Any] = [
                "url": self.browser.webView.url?.absoluteString ?? NSNull(),
                "host": self.browser.webView.url?.host ?? NSNull(),
                "title": self.browser.webView.title ?? NSNull(),
                "isLoading": self.browser.webView.isLoading,
                "estimatedProgress": self.browser.webView.estimatedProgress,
                "contentWorlds": [
                    "page": pageWorldObject ?? ["error": pageWorldError ?? "No page-world status returned."],
                    "defaultClient": defaultClientObject ?? ["error": defaultClientError ?? "No default-client status returned."],
                    BrowserModel.darkModeContentWorldName: darkModeWorldObject ?? ["error": darkModeWorldError ?? "No dark-mode content-world status returned."]
                ]
            ]

            if let pageWorldError {
                response["pageWorldError"] = pageWorldError
            }
            if let defaultClientError {
                response["defaultClientError"] = defaultClientError
            }
            if let darkModeWorldError {
                response["darkModeWorldError"] = darkModeWorldError
            }

            BrowserDebugLogging.log("[wkdomains-debug] local-api dark-mode done elapsed=\(Self.formatElapsed(since: startedAt)) \(self.pageStateDescription())")
            completion(.success(response))
        }

        browser.webView.evaluateJavaScript(script) { value, error in
            Task { @MainActor in
                if let error {
                    pageWorldError = error.localizedDescription
                } else if let object = decodeStatusObject(value) {
                    pageWorldObject = object
                } else {
                    pageWorldError = InspectionError.couldNotDecodePageJSON.localizedDescription
                }
                finishIfReady()
            }
        }

        browser.webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
            Task { @MainActor in
                switch result {
                case .success(let value):
                    if let object = decodeStatusObject(value) {
                        defaultClientObject = object
                    } else {
                        defaultClientError = InspectionError.couldNotDecodePageJSON.localizedDescription
                    }
                case .failure(let error):
                    defaultClientError = error.localizedDescription
                }
                finishIfReady()
            }
        }

        browser.webView.evaluateJavaScript(script, in: nil, in: BrowserModel.darkModeContentWorld) { result in
            Task { @MainActor in
                switch result {
                case .success(let value):
                    if let object = decodeStatusObject(value) {
                        darkModeWorldObject = object
                    } else {
                        darkModeWorldError = InspectionError.couldNotDecodePageJSON.localizedDescription
                    }
                case .failure(let error):
                    darkModeWorldError = error.localizedDescription
                }
                finishIfReady()
            }
        }
    }

    func readPendingBotRequests() -> [[String: Any]] {
        browser.pendingBotRequests().map(Self.dictionary(from:))
    }

    func waitForPendingBotRequests(timeout: TimeInterval, completion: @escaping (_ requests: [[String: Any]], _ timedOut: Bool) -> Void) {
        browser.waitForPendingBotRequests(timeout: timeout) { requests, timedOut in
            completion(requests.map(Self.dictionary(from:)), timedOut)
        }
    }

    func replyToBotRequest(id: UUID, summary: String) -> Bool {
        browser.replyToBotRequest(id: id, summary: summary)
    }

    func updateBotRequest(id: UUID, status: String) -> Bool {
        browser.updateBotRequest(id: id, status: status)
    }

    func readCurrentPage() -> [String: Any] {
        var response: [String: Any] = [:]

        if let url = browser.webView.url {
            response["url"] = url.absoluteString
            response["host"] = url.host
        }

        return response
    }

    private func currentPageDomain() throws -> RequestedDomain {
        guard let url = browser.webView.url,
              let domain = RequestedDomain(url: url)
        else {
            throw InspectionError.noPageLoaded
        }

        return domain
    }

    private func evaluateJSONScript(_ script: String, label: String, completion: @escaping (Result<Any, Error>) -> Void) {
        guard browser.webView.url != nil else {
            BrowserDebugLogging.log("[wkdomains-debug] local-api eval \(label) fail no-page")
            completion(.failure(InspectionError.noPageLoaded))
            return
        }

        let startedAt = Date()
        let startURL = browser.webView.url?.absoluteString ?? "nil"
        BrowserDebugLogging.log("[wkdomains-debug] local-api eval \(label) start \(pageStateDescription()) scriptBytes=\(script.utf8.count)")

        let slowWarning = DispatchWorkItem { [weak self] in
            guard let self else { return }
            BrowserDebugLogging.log(
                "[wkdomains-debug] local-api eval \(label) slow elapsed=\(Self.formatElapsed(since: startedAt)) startURL=\(startURL) \(self.pageStateDescription())"
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: slowWarning)

        browser.webView.evaluateJavaScript(script) { value, error in
            Task { @MainActor in
                slowWarning.cancel()
                if let error {
                    BrowserDebugLogging.log("[wkdomains-debug] local-api eval \(label) fail elapsed=\(Self.formatElapsed(since: startedAt)) error=\(error.localizedDescription) \(self.pageStateDescription())")
                    completion(.failure(error))
                    return
                }

                guard let json = value as? String,
                      let data = json.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data)
                else {
                    BrowserDebugLogging.log("[wkdomains-debug] local-api eval \(label) decode-fail elapsed=\(Self.formatElapsed(since: startedAt)) valueType=\(String(describing: type(of: value))) \(self.pageStateDescription())")
                    completion(.failure(InspectionError.couldNotDecodePageJSON))
                    return
                }

                BrowserDebugLogging.log("[wkdomains-debug] local-api eval \(label) done elapsed=\(Self.formatElapsed(since: startedAt)) jsonBytes=\(data.count) objectType=\(String(describing: type(of: object))) \(self.pageStateDescription())")
                completion(.success(object))
            }
        }
    }

    private func pageStateDescription() -> String {
        "url=\(browser.webView.url?.absoluteString ?? "nil") loading=\(browser.webView.isLoading) progress=\(String(format: "%.3f", browser.webView.estimatedProgress)) title=\(browser.webView.title ?? "nil")"
    }

    private static func formatElapsed(since startedAt: Date) -> String {
        String(format: "%.3fs", Date().timeIntervalSince(startedAt))
    }

    private static func cookie(_ cookie: HTTPCookie, matches host: String) -> Bool {
        let cookieDomain = cookie.domain
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return cookieDomain == host
            || cookieDomain.hasSuffix(".\(host)")
            || host.hasSuffix(".\(cookieDomain)")
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

    private static func originString(from url: URL) -> String {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port

        return components.url?.absoluteString ?? url.absoluteString
    }

    private static func dictionary(from request: BotTerminalRequest) -> [String: Any] {
        [
            "id": request.id.uuidString,
            "createdAt": iso8601Formatter.string(from: request.createdAt),
            "currentURL": request.currentURL,
            "pageHost": request.pageHost,
            "domain": request.domain,
            "llmsURL": request.llmsURL,
            "userAgent": request.userAgent,
            "prompt": request.prompt,
            "status": request.status
        ]
    }

    private static func resourceCandidates(for domain: String) -> [URL] {
        [
            "/llms.txt",
            "/llms-full.txt",
            "/openapi.json",
            "/swagger.json",
            "/.well-known/openapi.json",
            "/.well-known/ai-plugin.json",
            "/.well-known/agent-card.json",
            "/sitemap.xml",
            "/robots.txt"
        ].compactMap { path in
            URL(string: "https://\(domain)\(path)")
        }
    }

    private static func fetchResource(_ url: URL) async -> DomainResourceResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue(BotTerminalModel.llmsUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=0-8191", forHTTPHeaderField: "Range")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let contentType = httpResponse?.value(forHTTPHeaderField: "Content-Type")
            let contentLength = httpResponse?.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init)
            let isText = contentType?.lowercased().contains("text") == true
                || contentType?.lowercased().contains("json") == true
                || contentType?.lowercased().contains("xml") == true

            let preview: String?
            if isText, let text = String(data: data, encoding: .utf8) {
                preview = String(text.prefix(1200))
            } else {
                preview = nil
            }

            return DomainResourceResponse(
                url: url.absoluteString,
                path: url.path,
                status: httpResponse?.statusCode,
                found: (200..<400).contains(httpResponse?.statusCode ?? 0),
                contentType: contentType,
                contentLength: contentLength,
                sampledBytes: data.count,
                bodyPreview: preview,
                error: nil
            )
        } catch {
            return DomainResourceResponse(
                url: url.absoluteString,
                path: url.path,
                status: nil,
                found: false,
                contentType: nil,
                contentLength: nil,
                sampledBytes: 0,
                bodyPreview: nil,
                error: error.localizedDescription
            )
        }
    }

    static func fetchXHRJSON(
        xhr: XHRRequestResponse,
        url: URL,
        cookieHeader: String?
    ) async throws -> XHRReplayResponse {
        var request = URLRequest(url: url)
        request.httpMethod = xhr.method
        request.timeoutInterval = 30

        for (name, value) in xhr.requestHeaders {
            guard shouldReplayHeader(name) else {
                continue
            }

            request.setValue(value, forHTTPHeaderField: name)
        }

        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        }

        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(xhr.userAgent ?? BotTerminalModel.llmsUserAgent, forHTTPHeaderField: "User-Agent")
        }

        if let cookieHeader, !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        if let pageURL = xhr.pageURL {
            if request.value(forHTTPHeaderField: "Referer") == nil {
                request.setValue(pageURL, forHTTPHeaderField: "Referer")
            }

            if request.value(forHTTPHeaderField: "Origin") == nil,
               let origin = URL(string: pageURL).map(Self.originString(from:)) {
                request.setValue(origin, forHTTPHeaderField: "Origin")
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode

        guard !data.isEmpty else {
            throw InspectionError.xhrReplayReturnedEmptyBody(statusCode)
        }

        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw InspectionError.xhrReplayReturnedNonJSON(statusCode)
        }

        let responseContentType = httpResponse?.value(forHTTPHeaderField: "Content-Type")
        let contentType: String
        if responseContentType?.lowercased().contains("json") == true {
            contentType = responseContentType ?? "application/json; charset=utf-8"
        } else {
            contentType = "application/json; charset=utf-8"
        }

        return XHRReplayResponse(
            body: data,
            contentType: contentType
        )
    }

    private static func shouldReplayHeader(_ name: String) -> Bool {
        switch name.lowercased() {
        case "accept-encoding",
            "connection",
            "content-length",
            "cookie",
            "host",
            "proxy-authorization",
            "te",
            "trailer",
            "transfer-encoding",
            "upgrade":
            return false
        default:
            return true
        }
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
