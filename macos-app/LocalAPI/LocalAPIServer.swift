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
    private var debugRequestCounter = 0

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
        let debugID = nextDebugRequestID()
        BrowserDebugLogging.log("[wkdomains-debug] local-api request begin id=\(debugID) method=\(request.method) path=\(request.path)")

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

        if request.path == "/api/v1/cookies" {
            BrowserDebugLogging.log("[wkdomains-debug] local-api cookies start id=\(debugID)")
            dataReader.readStorageForCurrentPage { [weak self] result in
                switch result {
                case .success(let response):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api cookies done id=\(debugID) cookies=\(response.cookies.count)")
                    self?.sendJSON(response, status: .ok, on: connection)
                case .failure(let error):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api cookies fail id=\(debugID) error=\(error.localizedDescription)")
                    self?.sendError(status: .serviceUnavailable, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path == "/api/v1/xhr" {
            switch dataReader.readXHRRequestsForCurrentPage() {
            case .success(let response):
                BrowserDebugLogging.log("[wkdomains-debug] local-api xhr done id=\(debugID) requests=\(response.requests.count)")
                sendJSON(response, status: .ok, on: connection)
            case .failure(let error):
                BrowserDebugLogging.log("[wkdomains-debug] local-api xhr fail id=\(debugID) error=\(error.localizedDescription)")
                sendError(status: .serviceUnavailable, message: error.localizedDescription, on: connection)
            }
            return
        }

        if let index = request.xhrReplayIndex {
            dataReader.replayXHRRequestForCurrentPage(at: index) { [weak self] result in
                switch result {
                case .success(let response):
                    self?.sendData(
                        response.body,
                        contentType: response.contentType ?? "application/json; charset=utf-8",
                        status: .ok,
                        on: connection
                    )
                case .failure(let error):
                    self?.sendError(status: .serviceUnavailable, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path == "/api/v1/screenshot" {
            BrowserDebugLogging.log("[wkdomains-debug] local-api screenshot start id=\(debugID)")
            dataReader.readScreenshot { [weak self] result in
                switch result {
                case .success(let pngData):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api screenshot done id=\(debugID) bytes=\(pngData.count)")
                    self?.sendData(pngData, contentType: "image/png", status: .ok, on: connection)
                case .failure(let error):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api screenshot fail id=\(debugID) error=\(error.localizedDescription)")
                    self?.sendError(status: .serviceUnavailable, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path == "/api/v1/page" {
            let response = dataReader.readPage()
            BrowserDebugLogging.log("[wkdomains-debug] local-api page done id=\(debugID) url=\(response.url ?? "nil") loading=\(response.isLoading)")
            sendJSON(response, status: .ok, on: connection)
            return
        }

        if request.path == "/api/v1/console" {
            let response = dataReader.readConsoleMessages()
            BrowserDebugLogging.log("[wkdomains-debug] local-api console done id=\(debugID) messages=\(response.messages.count)")
            sendJSON(response, status: .ok, on: connection)
            return
        }

        if request.path == "/api/v1/dom" {
            BrowserDebugLogging.log("[wkdomains-debug] local-api dom start id=\(debugID)")
            dataReader.readDOM { [weak self] result in
                switch result {
                case .success(let response):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api dom done id=\(debugID) type=\(String(describing: type(of: response)))")
                    self?.sendJSONObject(response, contentType: "application/json; charset=utf-8", status: .ok, on: connection)
                case .failure(let error):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api dom fail id=\(debugID) error=\(error.localizedDescription)")
                    self?.sendError(status: .serviceUnavailable, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path == "/api/v1/links" {
            BrowserDebugLogging.log("[wkdomains-debug] local-api links start id=\(debugID)")
            dataReader.readLinks { [weak self] result in
                switch result {
                case .success(let response):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api links done id=\(debugID) type=\(String(describing: type(of: response)))")
                    self?.sendJSONObject(response, contentType: "application/json; charset=utf-8", status: .ok, on: connection)
                case .failure(let error):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api links fail id=\(debugID) error=\(error.localizedDescription)")
                    self?.sendError(status: .serviceUnavailable, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path == "/api/v1/resources" {
            BrowserDebugLogging.log("[wkdomains-debug] local-api resources start id=\(debugID)")
            dataReader.readResources { [weak self] response in
                BrowserDebugLogging.log("[wkdomains-debug] local-api resources done id=\(debugID) resources=\(response.resources.count)")
                self?.sendJSON(response, status: .ok, on: connection)
            }
            return
        }

        if request.path == "/api/v1/dark-mode" {
            BrowserDebugLogging.log("[wkdomains-debug] local-api dark-mode start id=\(debugID)")
            dataReader.readDarkModeStatus { [weak self] result in
                switch result {
                case .success(let response):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api dark-mode done id=\(debugID)")
                    self?.sendJSONObject(response, contentType: "application/json; charset=utf-8", status: .ok, on: connection)
                case .failure(let error):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api dark-mode fail id=\(debugID) error=\(error.localizedDescription)")
                    self?.sendError(status: .serviceUnavailable, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        sendError(status: .notFound, message: "Endpoint not found.", on: connection)
    }

    private func nextDebugRequestID() -> String {
        debugRequestCounter += 1
        return String(format: "%04d", debugRequestCounter)
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
