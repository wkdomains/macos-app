//
//  LocalAPIServer+Responses.swift
//  macos-app
//

import Foundation
@preconcurrency import Network

@MainActor
extension LocalAPIServer {
    func jsonBody(from request: HTTPRequest) -> [String: Any]? {
        guard !request.body.isEmpty,
              let jsonObject = try? JSONSerialization.jsonObject(with: request.body)
        else {
            return nil
        }

        return jsonObject as? [String: Any]
    }

    func captureScreenshotID(from path: String) -> String? {
        let prefix = "/api/v1/captures/"
        let suffix = "/screenshot"
        guard path.hasPrefix(prefix), path.hasSuffix(suffix) else {
            return nil
        }

        let start = path.index(path.startIndex, offsetBy: prefix.count)
        let end = path.index(path.endIndex, offsetBy: -suffix.count)
        guard start < end else {
            return nil
        }

        return String(path[start..<end])
    }

    func capturePayload(from output: ViewportCaptureOutput) -> [String: Any] {
        let screenshot: [String: Any]
        if let screenshotPNG = output.screenshotPNG {
            storeCaptureScreenshot(id: output.id, data: screenshotPNG)
            screenshot = [
                "available": true,
                "endpoint": "/api/v1/captures/\(output.id)/screenshot",
                "contentType": "image/png",
                "bytes": screenshotPNG.count
            ]
        } else {
            screenshot = [
                "available": false,
                "endpoint": NSNull(),
                "contentType": "image/png"
            ]
        }

        return [
            "id": output.id,
            "name": output.name,
            "requestedViewport": [
                "width": output.requestedWidth,
                "height": output.requestedHeight
            ],
            "page": output.page,
            "screenshot": screenshot,
            "snapshot": output.snapshot,
            "diagnostics": output.diagnostics
        ]
    }

    func visualComparisonPayload(from output: VisualComparisonOutput) -> [String: Any] {
        let diff: [String: Any]
        if let diffPNG = output.diffPNG {
            let diffID = "\(output.id)-diff"
            storeCaptureScreenshot(id: diffID, data: diffPNG)
            diff = [
                "available": true,
                "endpoint": "/api/v1/captures/\(diffID)/screenshot",
                "contentType": "image/png",
                "bytes": diffPNG.count
            ]
        } else {
            diff = [
                "available": false,
                "endpoint": NSNull(),
                "contentType": "image/png"
            ]
        }

        return [
            "id": output.id,
            "name": output.name,
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "metrics": output.metrics,
            "reference": capturePayload(from: output.reference),
            "current": capturePayload(from: output.current),
            "diff": diff
        ]
    }

    func storeCaptureScreenshot(id: String, data: Data) {
        captureScreenshots[id] = data
        captureScreenshotOrder.removeAll { $0 == id }
        captureScreenshotOrder.append(id)

        while captureScreenshotOrder.count > 24 {
            let removedID = captureScreenshotOrder.removeFirst()
            captureScreenshots.removeValue(forKey: removedID)
        }
    }

    func isLoopback(_ endpoint: NWEndpoint) -> Bool {
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

    func sendError(status: HTTPStatus, message: String, on connection: NWConnection) {
        sendJSON(APIErrorResponse(error: message), status: status, on: connection)
    }

    func sendMCPResult(id: Any?, result: [String: Any], on connection: NWConnection) {
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

    func sendMCPToolResult(id: Any?, value: Any, on connection: NWConnection) {
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

    func sendMCPError(id: Any?, code: Int, message: String, on connection: NWConnection) {
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

    func sendJSON<T: Encodable>(
        _ value: T,
        status: HTTPStatus,
        sortedKeys: Bool = true,
        on connection: NWConnection
    ) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = sortedKeys ? [.prettyPrinted, .sortedKeys] : [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601

        let body = (try? encoder.encode(value)) ?? Data(#"{"error":"Could not encode response."}"#.utf8)
        sendData(body, contentType: "application/json; charset=utf-8", status: status, on: connection)
    }

    func sendJSONObject(_ value: Any, contentType: String, status: HTTPStatus, on connection: NWConnection) {
        let body = (try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]))
            ?? Data(#"{"error":"Could not encode response."}"#.utf8)
        sendData(body, contentType: contentType, status: status, on: connection)
    }

    func sendEmpty(status: HTTPStatus, on connection: NWConnection) {
        sendData(Data(), contentType: "text/plain; charset=utf-8", status: status, on: connection)
    }

    func sendData(_ body: Data, contentType: String, status: HTTPStatus, on connection: NWConnection) {
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
