//
//  LocalAPIServer.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import Foundation
@preconcurrency import Network
@preconcurrency import WebKit

@MainActor
final class LocalAPIServer {
    private let dataReader: WebsiteDataReader
    private let requestedPort: UInt16
    private let queue = DispatchQueue.main
    private var listener: NWListener?

    init(browser: BrowserModel, settings: AppSettings) {
        dataReader = WebsiteDataReader(browser: browser)
        requestedPort = settings.port
    }

    func start() {
        startListening(startingAt: requestedPort, remainingAttempts: 20)
    }

    private func startListening(startingAt port: UInt16, remainingAttempts: Int) {
        guard remainingAttempts > 0, let nwPort = NWEndpoint.Port(rawValue: port) else {
            return
        }

        do {
            let nextListener = try NWListener(using: .tcp, on: nwPort)
            listener = nextListener

            nextListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    if case .failed = state {
                        let nextPort = port == UInt16.max ? AppSettings.defaultPort : port + 1
                        self.listener?.cancel()
                        self.listener = nil
                        self.startListening(startingAt: nextPort, remainingAttempts: remainingAttempts - 1)
                    }
                }
            }

            nextListener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handle(connection)
                }
            }

            nextListener.start(queue: queue)
        } catch {
            let nextPort = port == UInt16.max ? AppSettings.defaultPort : port + 1
            startListening(startingAt: nextPort, remainingAttempts: remainingAttempts - 1)
        }
    }

    private func handle(_ connection: NWConnection) {
        guard isLoopback(connection.endpoint) else {
            connection.cancel()
            return
        }

        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, error in
            Task { @MainActor [weak self] in
                guard let self else {
                    connection.cancel()
                    return
                }

                if let error {
                    self.sendError(status: .badRequest, message: error.localizedDescription, on: connection)
                    return
                }

                guard let data,
                      let request = HTTPRequest(data: data)
                else {
                    self.sendError(status: .badRequest, message: "Could not parse HTTP request.", on: connection)
                    return
                }

                self.route(request, connection: connection)
            }
        }
    }

    private func route(_ request: HTTPRequest, connection: NWConnection) {
        guard request.method == "GET" else {
            sendError(status: .methodNotAllowed, message: "Only GET is supported.", on: connection)
            return
        }

        if request.path.hasPrefix("/api/v1/cookies/") {
            let rawDomain = String(request.path.dropFirst("/api/v1/cookies/".count))
            guard let domain = RequestedDomain(rawValue: rawDomain) else {
                sendError(status: .badRequest, message: "Provide a valid domain.", on: connection)
                return
            }

            dataReader.readStorage(for: domain) { [weak self] response in
                self?.sendJSON(response, status: .ok, on: connection)
            }
            return
        }

        if request.path.hasPrefix("/api/v1/xhr/") {
            let rawHostname = String(request.path.dropFirst("/api/v1/xhr/".count))
            guard let domain = RequestedDomain(rawValue: rawHostname) else {
                sendError(status: .badRequest, message: "Provide a valid hostname.", on: connection)
                return
            }

            sendJSON(dataReader.readXHRRequests(for: domain), status: .ok, on: connection)
            return
        }

        sendError(status: .notFound, message: "Endpoint not found.", on: connection)
    }

    private func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .name(let name, _):
                return name == "localhost"
            case .ipv4(let address):
                return address == .loopback
            case .ipv6(let address):
                return address == .loopback
            @unknown default:
                return false
            }
        default:
            return false
        }
    }

    private func sendError(status: HTTPStatus, message: String, on connection: NWConnection) {
        sendJSON(APIErrorResponse(error: message), status: status, on: connection)
    }

    private func sendJSON<T: Encodable>(_ value: T, status: HTTPStatus, on connection: NWConnection) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let body = (try? encoder.encode(value)) ?? Data(#"{"error":"Could not encode response."}"#.utf8)
        let headers = [
            "HTTP/1.1 \(status.rawValue) \(status.reason)",
            "Content-Type: application/json; charset=utf-8",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "Access-Control-Allow-Origin: http://127.0.0.1",
            "",
            ""
        ].joined(separator: "\r\n")

        var response = Data(headers.utf8)
        response.append(body)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private struct HTTPRequest {
    let method: String
    let path: String

    init?(data: Data) {
        guard let text = String(data: data, encoding: .utf8),
              let requestLine = text.components(separatedBy: "\r\n").first
        else {
            return nil
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else {
            return nil
        }

        method = parts[0].uppercased()

        let target = parts[1]
        if let components = URLComponents(string: target) {
            path = components.percentEncodedPath.removingPercentEncoding ?? components.path
        } else {
            path = target
        }
    }
}

private struct RequestedDomain {
    let rawValue: String
    let host: String
    let port: Int?

    init?(rawValue: String) {
        let decoded = (rawValue.removingPercentEncoding ?? rawValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !decoded.isEmpty,
              decoded.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !decoded.contains("/")
        else {
            return nil
        }

        let candidate = decoded.contains("://") ? decoded : "https://\(decoded)"
        guard let components = URLComponents(string: candidate),
              let host = components.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              !host.isEmpty
        else {
            return nil
        }

        self.rawValue = decoded
        self.host = host
        self.port = components.port
    }
}

private enum HTTPStatus: Int {
    case ok = 200
    case badRequest = 400
    case notFound = 404
    case methodNotAllowed = 405

    var reason: String {
        switch self {
        case .ok:
            return "OK"
        case .badRequest:
            return "Bad Request"
        case .notFound:
            return "Not Found"
        case .methodNotAllowed:
            return "Method Not Allowed"
        }
    }
}

private struct APIErrorResponse: Encodable {
    let error: String
}

@MainActor
private final class WebsiteDataReader {
    private let browser: BrowserModel
    private let dataStore: WKWebsiteDataStore
    private let localStorageReader: LocalStorageReader

    init(browser: BrowserModel) {
        self.browser = browser
        self.dataStore = browser.webView.configuration.websiteDataStore
        localStorageReader = LocalStorageReader(dataStore: dataStore)
    }

    func readStorage(for domain: RequestedDomain, completion: @escaping (DomainStorageResponse) -> Void) {
        dataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self else { return }

                let matchingCookies = cookies
                    .filter { self.cookie($0, matches: domain.host) }
                    .map(CookieResponse.init(cookie:))
                    .sorted { left, right in
                        if left.domain == right.domain {
                            return left.name < right.name
                        }

                        return left.domain < right.domain
                    }

                self.localStorageReader.readLocalStorage(for: domain.localStorageOrigins) { localStorageOrigins in
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

    func readXHRRequests(for domain: RequestedDomain) -> XHRRequestsResponse {
        let requests = browser.xhrRequests(for: domain.host)
            .map(XHRRequestResponse.init(record:))
            .sorted { left, right in
                let leftBytes = left.responseBytes ?? -1
                let rightBytes = right.responseBytes ?? -1

                if leftBytes == rightBytes {
                    return left.startedAt < right.startedAt
                }

                return leftBytes > rightBytes
            }

        return XHRRequestsResponse(
            hostname: domain.host,
            activePageURL: browser.webView.url?.absoluteString,
            activePageHost: browser.webView.url?.host,
            requests: requests
        )
    }

    private func cookie(_ cookie: HTTPCookie, matches host: String) -> Bool {
        let cookieDomain = cookie.domain
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return cookieDomain == host
            || cookieDomain.hasSuffix(".\(host)")
            || host.hasSuffix(".\(cookieDomain)")
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
}

private extension RequestedDomain {
    var localStorageOrigins: [URL] {
        var hosts = [host]

        if host.hasPrefix("www.") {
            hosts.append(String(host.dropFirst(4)))
        } else if !isLocalHostLike {
            hosts.append("www.\(host)")
        }

        var urls: [URL] = []
        var seen = Set<String>()
        let schemes = isLocalHostLike ? ["http", "https"] : ["https", "http"]

        for scheme in schemes {
            for host in hosts {
                var components = URLComponents()
                components.scheme = scheme
                components.host = host
                components.port = port
                components.path = "/"

                guard let url = components.url else {
                    continue
                }

                let key = url.absoluteString
                if seen.insert(key).inserted {
                    urls.append(url)
                }
            }
        }

        return urls
    }

    var isLocalHostLike: Bool {
        host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
    }

    func matches(host candidate: String) -> Bool {
        let candidate = candidate.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return candidate == host
            || candidate.hasSuffix(".\(host)")
            || host.hasSuffix(".\(candidate)")
    }
}

private struct DomainStorageResponse: Encodable {
    let domain: String
    let cookies: [CookieResponse]
    let localStorage: [LocalStorageOriginResponse]
    let sessionStorage: [SessionStorageOriginResponse]
}

private struct XHRRequestsResponse: Encodable {
    let hostname: String
    let activePageURL: String?
    let activePageHost: String?
    let requests: [XHRRequestResponse]
}

private struct XHRRequestResponse: Encodable {
    let id: String
    let kind: String
    let method: String
    let url: String
    let host: String?
    let pageURL: String?
    let pageHost: String?
    let startedAt: Date
    let completedAt: Date?
    let status: Int?
    let responseURL: String?
    let responseBytes: Int?
    let jsonType: String?
    let jsonItems: Int?
    let jsonShape: String?
    let error: String?

    init(record: XHRRequestRecord) {
        id = record.id
        kind = record.kind
        method = record.method
        url = record.url
        host = record.host
        pageURL = record.pageURL
        pageHost = record.pageHost
        startedAt = record.startedAt
        completedAt = record.completedAt
        status = record.status
        responseURL = record.responseURL
        responseBytes = record.responseBytes
        jsonType = record.jsonType
        jsonItems = record.jsonItems
        jsonShape = record.jsonShape
        error = record.error
    }
}

private struct CookieResponse: Encodable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresAt: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool
    let sameSitePolicy: String?

    init(cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expiresAt = cookie.expiresDate
        isSecure = cookie.isSecure
        isHTTPOnly = cookie.isHTTPOnly
        sameSitePolicy = cookie.sameSitePolicy?.rawValue
    }
}

private struct LocalStorageOriginResponse: Encodable {
    let origin: String
    let items: [StorageItem]
    let error: String?
}

private struct SessionStorageOriginResponse: Encodable {
    let origin: String
    let items: [StorageItem]
    let error: String?
}

private struct StorageItem: Codable {
    let key: String
    let value: String?
}

@MainActor
private final class LocalStorageReader {
    private let dataStore: WKWebsiteDataStore
    private var sessions: [ObjectIdentifier: LocalStorageSession] = [:]

    init(dataStore: WKWebsiteDataStore) {
        self.dataStore = dataStore
    }

    func readLocalStorage(for origins: [URL], completion: @escaping ([LocalStorageOriginResponse]) -> Void) {
        guard !origins.isEmpty else {
            completion([])
            return
        }

        var pending = origins.count
        var results: [LocalStorageOriginResponse] = []

        for origin in origins {
            var session: LocalStorageSession?
            session = LocalStorageSession(origin: origin, dataStore: dataStore) { [weak self] result in
                if let session {
                    self?.sessions.removeValue(forKey: ObjectIdentifier(session))
                }

                results.append(result)
                pending -= 1

                if pending == 0 {
                    completion(results.sorted { $0.origin < $1.origin })
                }
            }

            if let session {
                sessions[ObjectIdentifier(session)] = session
                session.start()
            }
        }
    }
}

@MainActor
private final class LocalStorageSession: NSObject, WKNavigationDelegate {
    private let origin: URL
    private let webView: WKWebView
    private let completion: (LocalStorageOriginResponse) -> Void
    private var completed = false

    init(origin: URL, dataStore: WKWebsiteDataStore, completion: @escaping (LocalStorageOriginResponse) -> Void) {
        self.origin = origin
        self.completion = completion

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        webView.navigationDelegate = self
    }

    func start() {
        webView.loadHTMLString("<!doctype html><title></title>", baseURL: origin)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        readLocalStorage()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(items: [], error: error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(items: [], error: error.localizedDescription)
    }

    private func readLocalStorage() {
        let script = """
        JSON.stringify(Array.from({ length: localStorage.length }, (_, index) => {
            const key = localStorage.key(index);
            return { key, value: localStorage.getItem(key) };
        }))
        """

        webView.evaluateJavaScript(script) { [weak self] value, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    self.finish(items: [], error: error.localizedDescription)
                    return
                }

                guard let json = value as? String,
                      let data = json.data(using: .utf8),
                      let items = try? JSONDecoder().decode([StorageItem].self, from: data)
                else {
                    self.finish(items: [], error: "Could not decode localStorage.")
                    return
                }

                self.finish(items: items.sorted { $0.key < $1.key }, error: nil)
            }
        }
    }

    private func finish(items: [StorageItem], error: String?) {
        guard !completed else { return }
        completed = true

        var components = URLComponents()
        components.scheme = origin.scheme
        components.host = origin.host
        components.port = origin.port

        completion(
            LocalStorageOriginResponse(
                origin: components.url?.absoluteString ?? origin.absoluteString,
                items: items,
                error: error
            )
        )
    }
}
