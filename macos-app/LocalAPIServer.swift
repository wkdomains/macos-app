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
        if request.path == "/mcp" {
            routeMCP(request, connection: connection)
            return
        }

        if request.method == "OPTIONS" {
            sendEmpty(status: .accepted, on: connection)
            return
        }

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

        if request.path == "/api/v1/screenshot" {
            dataReader.readScreenshot { [weak self] result in
                switch result {
                case .success(let pngData):
                    self?.sendData(pngData, contentType: "image/png", status: .ok, on: connection)
                case .failure(let error):
                    self?.sendError(status: .serviceUnavailable, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path == "/api/v1/page" {
            sendJSON(dataReader.readPage(), status: .ok, on: connection)
            return
        }

        if request.path == "/api/v1/console" {
            sendJSON(dataReader.readConsoleMessages(), status: .ok, on: connection)
            return
        }

        if request.path == "/api/v1/dom" {
            dataReader.readDOM { [weak self] result in
                switch result {
                case .success(let response):
                    self?.sendJSONObject(response, contentType: "application/json; charset=utf-8", status: .ok, on: connection)
                case .failure(let error):
                    self?.sendError(status: .serviceUnavailable, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path == "/api/v1/links" {
            dataReader.readLinks { [weak self] result in
                switch result {
                case .success(let response):
                    self?.sendJSONObject(response, contentType: "application/json; charset=utf-8", status: .ok, on: connection)
                case .failure(let error):
                    self?.sendError(status: .serviceUnavailable, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path == "/api/v1/resources" {
            dataReader.readResources { [weak self] response in
                self?.sendJSON(response, status: .ok, on: connection)
            }
            return
        }

        sendError(status: .notFound, message: "Endpoint not found.", on: connection)
    }

    private func routeMCP(_ request: HTTPRequest, connection: NWConnection) {
        guard request.method != "GET" else {
            sendError(status: .methodNotAllowed, message: "This MCP endpoint does not provide an SSE stream.", on: connection)
            return
        }

        guard request.method == "POST" else {
            sendError(status: .methodNotAllowed, message: "Use POST for MCP JSON-RPC messages.", on: connection)
            return
        }

        guard request.originIsAllowed else {
            sendError(status: .badRequest, message: "Origin is not allowed.", on: connection)
            return
        }

        guard let jsonObject = try? JSONSerialization.jsonObject(with: request.body),
              let message = jsonObject as? [String: Any]
        else {
            sendMCPError(id: nil, code: -32700, message: "Invalid JSON-RPC request.", on: connection)
            return
        }

        guard let method = message["method"] as? String else {
            sendEmpty(status: .accepted, on: connection)
            return
        }

        let id = message["id"]

        guard id != nil else {
            sendEmpty(status: .accepted, on: connection)
            return
        }

        switch method {
        case "initialize":
            sendMCPResult(
                id: id,
                result: [
                    "protocolVersion": "2025-06-18",
                    "capabilities": [
                        "tools": [:]
                    ],
                    "serverInfo": [
                        "name": "wkdomains",
                        "version": "0.0.1"
                    ]
                ],
                on: connection
            )
        case "tools/list":
            sendMCPResult(id: id, result: ["tools": mcpTools], on: connection)
        case "tools/call":
            guard let params = message["params"] as? [String: Any],
                  let toolName = params["name"] as? String
            else {
                sendMCPError(id: id, code: -32602, message: "Missing tool name.", on: connection)
                return
            }

            let arguments = params["arguments"] as? [String: Any] ?? [:]
            callMCPTool(named: toolName, arguments: arguments, id: id, connection: connection)
        default:
            sendMCPError(id: id, code: -32601, message: "Method not found.", on: connection)
        }
    }

    private var mcpTools: [[String: Any]] {
        [
            [
                "name": "get_human_requests",
                "description": "Return pending requests created by the human in wkdomains, including the current URL, derived domain, llms.txt URL, and required user-agent.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:],
                    "additionalProperties": false
                ]
            ],
            [
                "name": "wait_for_human_request",
                "description": "Long-poll for a pending request created by the human in wkdomains. Returns immediately if a request is already pending; otherwise waits until one appears or the timeout expires.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "timeoutMs": [
                            "type": "integer",
                            "description": "How long to wait before returning with no request. Defaults to 30000 and is capped at 120000."
                        ]
                    ],
                    "additionalProperties": false
                ]
            ],
            [
                "name": "reply_to_human_request",
                "description": "Send a terminal reply for a pending human request.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "requestId": [
                            "type": "string",
                            "description": "The pending request id."
                        ],
                        "summary": [
                            "type": "string",
                            "description": "The summary or answer to display in the terminal."
                        ]
                    ],
                    "required": ["requestId", "summary"],
                    "additionalProperties": false
                ]
            ],
            [
                "name": "update_human_request_status",
                "description": "Send a short progress update for a pending human request without completing it. Use this before longer API calls or investigations so the wkdomains terminal does not look stuck.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "requestId": [
                            "type": "string",
                            "description": "The pending request id."
                        ],
                        "status": [
                            "type": "string",
                            "description": "A short progress update to show in the terminal."
                        ]
                    ],
                    "required": ["requestId", "status"],
                    "additionalProperties": false
                ]
            ],
            [
                "name": "get_current_page",
                "description": "Return the current browser URL and host.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:],
                    "additionalProperties": false
                ]
            ]
        ]
    }

    private func callMCPTool(
        named toolName: String,
        arguments: [String: Any],
        id: Any?,
        connection: NWConnection
    ) {
        switch toolName {
        case "get_human_requests":
            let requests = dataReader.readPendingBotRequests()
            sendMCPToolResult(id: id, value: ["requests": requests], on: connection)
        case "wait_for_human_request":
            let rawTimeoutMs = arguments["timeoutMs"] as? Int ?? 30_000
            let timeoutMs = min(max(rawTimeoutMs, 1_000), 120_000)

            dataReader.waitForPendingBotRequests(timeout: TimeInterval(timeoutMs) / 1_000) { [weak self] requests, timedOut in
                self?.sendMCPToolResult(
                    id: id,
                    value: [
                        "timedOut": timedOut,
                        "requests": requests
                    ],
                    on: connection
                )
            }
        case "reply_to_human_request":
            guard let requestId = arguments["requestId"] as? String,
                  let uuid = UUID(uuidString: requestId),
                  let summary = arguments["summary"] as? String
            else {
                sendMCPError(id: id, code: -32602, message: "Provide requestId and summary.", on: connection)
                return
            }

            guard dataReader.replyToBotRequest(id: uuid, summary: summary) else {
                sendMCPError(id: id, code: -32602, message: "Request not found.", on: connection)
                return
            }

            sendMCPToolResult(id: id, value: ["ok": true], on: connection)
        case "update_human_request_status":
            guard let requestId = arguments["requestId"] as? String,
                  let uuid = UUID(uuidString: requestId),
                  let status = arguments["status"] as? String
            else {
                sendMCPError(id: id, code: -32602, message: "Provide requestId and status.", on: connection)
                return
            }

            guard dataReader.updateBotRequest(id: uuid, status: status) else {
                sendMCPError(id: id, code: -32602, message: "Request not found.", on: connection)
                return
            }

            sendMCPToolResult(id: id, value: ["ok": true], on: connection)
        case "get_current_page":
            sendMCPToolResult(id: id, value: dataReader.readCurrentPage(), on: connection)
        default:
            sendMCPError(id: id, code: -32602, message: "Unknown tool.", on: connection)
        }
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

    private func sendMCPResult(id: Any?, result: [String: Any], on connection: NWConnection) {
        sendJSONObject(
            [
                "jsonrpc": "2.0",
                "id": id ?? NSNull(),
                "result": result
            ],
            contentType: "application/json; charset=utf-8",
            status: .ok,
            on: connection
        )
    }

    private func sendMCPToolResult(id: Any?, value: Any, on connection: NWConnection) {
        let text: String
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8)
        {
            text = json
        } else {
            text = String(describing: value)
        }

        sendMCPResult(
            id: id,
            result: [
                "content": [
                    [
                        "type": "text",
                        "text": text
                    ]
                ],
                "isError": false
            ],
            on: connection
        )
    }

    private func sendMCPError(id: Any?, code: Int, message: String, on connection: NWConnection) {
        sendJSONObject(
            [
                "jsonrpc": "2.0",
                "id": id ?? NSNull(),
                "error": [
                    "code": code,
                    "message": message
                ]
            ],
            contentType: "application/json; charset=utf-8",
            status: .ok,
            on: connection
        )
    }

    private func sendJSON<T: Encodable>(_ value: T, status: HTTPStatus, on connection: NWConnection) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let body = (try? encoder.encode(value)) ?? Data(#"{"error":"Could not encode response."}"#.utf8)
        sendData(body, contentType: "application/json; charset=utf-8", status: status, on: connection)
    }

    private func sendJSONObject(_ value: Any, contentType: String, status: HTTPStatus, on connection: NWConnection) {
        let body = (try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]))
            ?? Data(#"{"error":"Could not encode response."}"#.utf8)
        sendData(body, contentType: contentType, status: status, on: connection)
    }

    private func sendEmpty(status: HTTPStatus, on connection: NWConnection) {
        sendData(Data(), contentType: "text/plain; charset=utf-8", status: status, on: connection)
    }

    private func sendData(_ body: Data, contentType: String, status: HTTPStatus, on connection: NWConnection) {
        let headers = [
            "HTTP/1.1 \(status.rawValue) \(status.reason)",
            "Content-Type: \(contentType)",
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
    let headers: [String: String]
    let body: Data

    init?(data: Data) {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: delimiter),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8),
              let requestLine = headerText.components(separatedBy: "\r\n").first
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

        var parsedHeaders: [String: String] = [:]
        for line in headerText.components(separatedBy: "\r\n").dropFirst() {
            let headerParts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard headerParts.count == 2 else { continue }

            parsedHeaders[headerParts[0].lowercased()] = headerParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        headers = parsedHeaders
        body = data[headerRange.upperBound...]
    }

    var originIsAllowed: Bool {
        guard let origin = headers["origin"],
              let originURL = URL(string: origin),
              let host = originURL.host?.lowercased()
        else {
            return true
        }

        return host == "localhost" || host == "127.0.0.1" || host == "::1"
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
    case accepted = 202
    case badRequest = 400
    case notFound = 404
    case methodNotAllowed = 405
    case serviceUnavailable = 503

    var reason: String {
        switch self {
        case .ok:
            return "OK"
        case .accepted:
            return "Accepted"
        case .badRequest:
            return "Bad Request"
        case .notFound:
            return "Not Found"
        case .methodNotAllowed:
            return "Method Not Allowed"
        case .serviceUnavailable:
            return "Service Unavailable"
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
        evaluateJSONScript(BrowserModel.domInspectionScript, completion: completion)
    }

    func readLinks(completion: @escaping (Result<Any, Error>) -> Void) {
        evaluateJSONScript(BrowserModel.linksInspectionScript, completion: completion)
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

    private func evaluateJSONScript(_ script: String, completion: @escaping (Result<Any, Error>) -> Void) {
        guard browser.webView.url != nil else {
            completion(.failure(InspectionError.noPageLoaded))
            return
        }

        browser.webView.evaluateJavaScript(script) { value, error in
            Task { @MainActor in
                if let error {
                    completion(.failure(error))
                    return
                }

                guard let json = value as? String,
                      let data = json.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data)
                else {
                    completion(.failure(InspectionError.couldNotDecodePageJSON))
                    return
                }

                completion(.success(object))
            }
        }
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

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private enum InspectionError: LocalizedError {
    case noPageLoaded
    case couldNotDecodePageJSON

    var errorDescription: String? {
        switch self {
        case .noPageLoaded:
            return "No page is loaded."
        case .couldNotDecodePageJSON:
            return "Could not decode page inspection JSON."
        }
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

private struct PageResponse: Encodable {
    let url: String?
    let title: String?
    let host: String?
    let domain: String?
    let origin: String?
    let viewportMode: String
    let viewportWidth: Int
    let viewportHeight: Int
    let isLoading: Bool
    let canGoBack: Bool
    let canGoForward: Bool
}

private struct ConsoleMessagesResponse: Encodable {
    let activePageURL: String?
    let activePageHost: String?
    let captureScope: String
    let capturedLevels: [String]
    let messages: [ConsoleMessageResponse]
}

private struct ConsoleMessageResponse: Encodable {
    let id: UUID
    let level: String
    let message: String
    let arguments: [String]
    let pageURL: String?
    let pageHost: String?
    let stack: String?
    let createdAt: Date

    init(record: ConsoleMessageRecord) {
        id = record.id
        level = record.level
        message = record.message
        arguments = record.arguments
        pageURL = record.pageURL
        pageHost = record.pageHost
        stack = record.stack
        createdAt = record.createdAt
    }
}

private struct DomainResourcesResponse: Encodable {
    let domain: String?
    let pageHost: String?
    let resources: [DomainResourceResponse]
}

private struct DomainResourceResponse: Encodable {
    let url: String
    let path: String
    let status: Int?
    let found: Bool
    let contentType: String?
    let contentLength: Int?
    let sampledBytes: Int
    let bodyPreview: String?
    let error: String?
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
