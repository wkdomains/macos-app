//
//  LocalAPIServer+MCP.swift
//  macos-app
//

import Foundation
@preconcurrency import Network

@MainActor
extension LocalAPIServer {
    func routeMCP(_ request: HTTPRequest, connection: NWConnection) {
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

    var mcpTools: [[String: Any]] {
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

    func callMCPTool(
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
}
