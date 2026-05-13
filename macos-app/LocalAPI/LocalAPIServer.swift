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
    let dataReader: WebsiteDataReader
    let screenRecorder: ScreenRecorder
    private let requestedPort: UInt16
    private let queue = DispatchQueue.main
    private var listener: NWListener?
    private var boundPort: UInt16?
    private var debugRequestCounter = 0
    var portDidChange: ((UInt16) -> Void)?
    var captureScreenshots: [String: Data] = [:]
    var captureScreenshotOrder: [String] = []

    init(browser: BrowserModel, port: UInt16, screenRecorder: ScreenRecorder) {
        dataReader = WebsiteDataReader(browser: browser)
        self.screenRecorder = screenRecorder
        requestedPort = port
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

                    if case .ready = state {
                        self.boundPort = port
                        self.portDidChange?(port)
                    } else if case .failed = state {
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

        if request.path == "/api/v1/recording" || request.path.hasPrefix("/api/v1/recording/") {
            routeRecording(request, connection: connection)
            return
        }

        if request.path == "/api/v1/navigate" || request.path == "/api/v1/navgiate" {
            guard request.method == "POST" else {
                sendError(status: .methodNotAllowed, message: "Use POST for navigation requests.", on: connection)
                return
            }

            guard request.originIsAllowed else {
                sendError(status: .badRequest, message: "Origin is not allowed.", on: connection)
                return
            }

            guard let jsonObject = try? JSONSerialization.jsonObject(with: request.body),
                  let body = jsonObject as? [String: Any],
                  let url = body["url"] as? String
            else {
                sendError(status: .badRequest, message: InspectionError.invalidNavigationRequest.localizedDescription, on: connection)
                return
            }

            let mode = body["mode"] as? String
            BrowserDebugLogging.log("[wkdomains-debug] local-api navigate start id=\(debugID) mode=\(mode ?? "auto") url=\(url)")
            dataReader.navigate(to: url, mode: mode) { [weak self] result in
                switch result {
                case .success(let response):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api navigate done id=\(debugID)")
                    self?.sendJSONObject(response, contentType: "application/json; charset=utf-8", status: .ok, on: connection)
                case .failure(let error):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api navigate fail id=\(debugID) error=\(error.localizedDescription)")
                    self?.sendError(status: .badRequest, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path == "/api/v1/viewport" {
            if request.method == "GET" {
                sendJSONObject(dataReader.readViewport(), contentType: "application/json; charset=utf-8", status: .ok, on: connection)
                return
            }

            guard request.method == "POST" else {
                sendError(status: .methodNotAllowed, message: "Use GET or POST for viewport requests.", on: connection)
                return
            }

            guard request.originIsAllowed else {
                sendError(status: .badRequest, message: "Origin is not allowed.", on: connection)
                return
            }

            guard let body = jsonBody(from: request) else {
                sendError(status: .badRequest, message: InspectionError.invalidViewportRequest.localizedDescription, on: connection)
                return
            }

            dataReader.setViewport(arguments: body) { [weak self] result in
                switch result {
                case .success(let response):
                    self?.sendJSONObject(response, contentType: "application/json; charset=utf-8", status: .ok, on: connection)
                case .failure(let error):
                    self?.sendError(status: .badRequest, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path == "/api/v1/capture" {
            guard request.method == "POST" else {
                sendError(status: .methodNotAllowed, message: "Use POST for capture requests.", on: connection)
                return
            }

            guard request.originIsAllowed else {
                sendError(status: .badRequest, message: "Origin is not allowed.", on: connection)
                return
            }

            let body = jsonBody(from: request) ?? [:]
            dataReader.captureViewport(arguments: body) { [weak self] result in
                switch result {
                case .success(let output):
                    self?.sendJSONObject(self?.capturePayload(from: output) ?? [:], contentType: "application/json; charset=utf-8", status: .ok, on: connection)
                case .failure(let error):
                    self?.sendError(status: .serviceUnavailable, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path == "/api/v1/qa/viewports" {
            guard request.method == "POST" else {
                sendError(status: .methodNotAllowed, message: "Use POST for viewport QA requests.", on: connection)
                return
            }

            guard request.originIsAllowed else {
                sendError(status: .badRequest, message: "Origin is not allowed.", on: connection)
                return
            }

            let body = jsonBody(from: request) ?? [:]
            dataReader.captureViewports(arguments: body) { [weak self] result in
                switch result {
                case .success(let outputs):
                    let captures = outputs.map { self?.capturePayload(from: $0) ?? [:] }
                    self?.sendJSONObject(
                        [
                            "generatedAt": ISO8601DateFormatter().string(from: Date()),
                            "count": captures.count,
                            "captures": captures
                        ],
                        contentType: "application/json; charset=utf-8",
                        status: .ok,
                        on: connection
                    )
                case .failure(let error):
                    self?.sendError(status: .serviceUnavailable, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path == "/api/v1/visual/compare" || request.path == "/api/v1/visual-diff" {
            guard request.method == "POST" else {
                sendError(status: .methodNotAllowed, message: "Use POST for visual comparison requests.", on: connection)
                return
            }

            guard request.originIsAllowed else {
                sendError(status: .badRequest, message: "Origin is not allowed.", on: connection)
                return
            }

            guard let body = jsonBody(from: request) else {
                sendError(status: .badRequest, message: InspectionError.invalidVisualComparisonRequest.localizedDescription, on: connection)
                return
            }

            BrowserDebugLogging.log("[wkdomains-debug] local-api visual compare start id=\(debugID)")
            dataReader.compareVisual(arguments: body) { [weak self] result in
                switch result {
                case .success(let output):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api visual compare done id=\(debugID)")
                    self?.sendJSONObject(
                        self?.visualComparisonPayload(from: output) ?? [:],
                        contentType: "application/json; charset=utf-8",
                        status: .ok,
                        on: connection
                    )
                case .failure(let error):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api visual compare fail id=\(debugID) error=\(error.localizedDescription)")
                    self?.sendError(status: .serviceUnavailable, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path == "/api/v1/action" || request.path == "/api/v1/actions" {
            guard request.method == "POST" else {
                sendError(status: .methodNotAllowed, message: "Use POST for action requests.", on: connection)
                return
            }

            guard request.originIsAllowed else {
                sendError(status: .badRequest, message: "Origin is not allowed.", on: connection)
                return
            }

            guard let body = jsonBody(from: request) else {
                sendError(status: .badRequest, message: InspectionError.invalidActionRequest.localizedDescription, on: connection)
                return
            }

            BrowserDebugLogging.log("[wkdomains-debug] local-api action start id=\(debugID)")
            dataReader.performAction(arguments: body) { [weak self] result in
                switch result {
                case .success(let response):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api action done id=\(debugID)")
                    self?.sendJSONObject(response, contentType: "application/json; charset=utf-8", status: .ok, on: connection)
                case .failure(let error):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api action fail id=\(debugID) error=\(error.localizedDescription)")
                    self?.sendError(status: .badRequest, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path == "/api/v1/scenario" || request.path == "/api/v1/flow" {
            guard request.method == "POST" else {
                sendError(status: .methodNotAllowed, message: "Use POST for scenario requests.", on: connection)
                return
            }

            guard request.originIsAllowed else {
                sendError(status: .badRequest, message: "Origin is not allowed.", on: connection)
                return
            }

            guard let body = jsonBody(from: request) else {
                sendError(status: .badRequest, message: InspectionError.invalidScenarioRequest.localizedDescription, on: connection)
                return
            }

            BrowserDebugLogging.log("[wkdomains-debug] local-api scenario start id=\(debugID)")
            dataReader.runScenario(arguments: body) { [weak self] result in
                switch result {
                case .success(let response):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api scenario done id=\(debugID)")
                    self?.sendJSONObject(response, contentType: "application/json; charset=utf-8", status: .ok, on: connection)
                case .failure(let error):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api scenario fail id=\(debugID) error=\(error.localizedDescription)")
                    self?.sendError(status: .badRequest, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path == "/api/v1/scroll/record" {
            guard request.method == "POST" else {
                sendError(status: .methodNotAllowed, message: "Use POST for scroll recording requests.", on: connection)
                return
            }

            guard request.originIsAllowed else {
                sendError(status: .badRequest, message: "Origin is not allowed.", on: connection)
                return
            }

            BrowserDebugLogging.log("[wkdomains-debug] local-api scroll record start id=\(debugID)")
            dataReader.recordScrollTrace(arguments: jsonBody(from: request) ?? [:]) { [weak self] result in
                switch result {
                case .success(let response):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api scroll record done id=\(debugID)")
                    self?.sendJSONObject(response, contentType: "application/json; charset=utf-8", status: .ok, on: connection)
                case .failure(let error):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api scroll record fail id=\(debugID) error=\(error.localizedDescription)")
                    self?.sendError(status: .serviceUnavailable, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path == "/api/v1/console-panel" {
            if request.method == "GET" {
                sendJSONObject(
                    [
                        "visible": dataReader.browser.isConsolePanelVisible,
                        "messageCount": dataReader.browser.consoleRecords.count
                    ],
                    contentType: "application/json; charset=utf-8",
                    status: .ok,
                    on: connection
                )
                return
            }

            guard request.method == "POST" else {
                sendError(status: .methodNotAllowed, message: "Use GET or POST for console panel requests.", on: connection)
                return
            }

            guard request.originIsAllowed else {
                sendError(status: .badRequest, message: "Origin is not allowed.", on: connection)
                return
            }

            let body = jsonBody(from: request) ?? [:]
            let visible = body["visible"] as? Bool ?? false
            dataReader.browser.setConsolePanelVisible(visible)
            sendJSONObject(
                [
                    "visible": dataReader.browser.isConsolePanelVisible,
                    "messageCount": dataReader.browser.consoleRecords.count
                ],
                contentType: "application/json; charset=utf-8",
                status: .ok,
                on: connection
            )
            return
        }

        guard request.method == "GET" else {
            sendError(status: .methodNotAllowed, message: "Only GET is supported.", on: connection)
            return
        }

        if let captureScreenshotID = captureScreenshotID(from: request.path) {
            guard let screenshot = captureScreenshots[captureScreenshotID] else {
                sendError(status: .notFound, message: "Capture screenshot not found.", on: connection)
                return
            }

            sendData(screenshot, contentType: "image/png", status: .ok, on: connection)
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

        if request.path == "/api/v1/layout" {
            BrowserDebugLogging.log("[wkdomains-debug] local-api layout start id=\(debugID)")
            dataReader.readLayoutDiagnostics { [weak self] result in
                switch result {
                case .success(let response):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api layout done id=\(debugID)")
                    self?.sendJSONObject(response, contentType: "application/json; charset=utf-8", status: .ok, on: connection)
                case .failure(let error):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api layout fail id=\(debugID) error=\(error.localizedDescription)")
                    self?.sendError(status: .serviceUnavailable, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path.hasPrefix("/api/v1/element/") {
            let ref = String(request.path.dropFirst("/api/v1/element/".count))
            BrowserDebugLogging.log("[wkdomains-debug] local-api element start id=\(debugID) ref=\(ref)")
            dataReader.readElementXRay(ref: ref) { [weak self] result in
                switch result {
                case .success(let response):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api element done id=\(debugID) ref=\(ref)")
                    self?.sendJSONObject(response, contentType: "application/json; charset=utf-8", status: .ok, on: connection)
                case .failure(let error):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api element fail id=\(debugID) ref=\(ref) error=\(error.localizedDescription)")
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

        if request.path == "/api/v1/snapshot" {
            BrowserDebugLogging.log("[wkdomains-debug] local-api snapshot start id=\(debugID)")
            dataReader.readSnapshot { [weak self] result in
                switch result {
                case .success(let response):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api snapshot done id=\(debugID) type=\(String(describing: type(of: response)))")
                    self?.sendJSONObject(response, contentType: "application/json; charset=utf-8", status: .ok, on: connection)
                case .failure(let error):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api snapshot fail id=\(debugID) error=\(error.localizedDescription)")
                    self?.sendError(status: .serviceUnavailable, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path == "/api/v1/observe" {
            BrowserDebugLogging.log("[wkdomains-debug] local-api observe start id=\(debugID)")
            dataReader.readObserve { [weak self] result in
                switch result {
                case .success(let response):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api observe done id=\(debugID)")
                    self?.sendJSONObject(response, contentType: "application/json; charset=utf-8", status: .ok, on: connection)
                case .failure(let error):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api observe fail id=\(debugID) error=\(error.localizedDescription)")
                    self?.sendError(status: .serviceUnavailable, message: error.localizedDescription, on: connection)
                }
            }
            return
        }

        if request.path == "/api/v1/console" {
            let response = dataReader.readConsoleMessages()
            BrowserDebugLogging.log("[wkdomains-debug] local-api console done id=\(debugID) messages=\(response.messages.count)")
            sendJSON(response, status: .ok, on: connection)
            return
        }

        if request.path == "/api/v1/timing" {
            let page = dataReader.readPage()
            let response = BrowserDebugLogging.timingResponse(
                activePageURL: page.url,
                activePageHost: page.host
            )
            sendJSON(response, status: .ok, sortedKeys: false, on: connection)
            return
        }

        if request.path == "/api/v1/timing/reset" {
            let page = dataReader.readPage()
            BrowserDebugLogging.startTimingSession(
                pageURL: page.url,
                pageHost: page.host,
                reason: "api-reset"
            )
            let response = BrowserDebugLogging.timingResponse(
                activePageURL: page.url,
                activePageHost: page.host
            )
            sendJSON(response, status: .ok, sortedKeys: false, on: connection)
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

        if request.path == "/api/v1/scroll" || request.path == "/api/v1/scroll-trace" {
            BrowserDebugLogging.log("[wkdomains-debug] local-api scroll trace start id=\(debugID)")
            dataReader.readScrollTrace { [weak self] result in
                switch result {
                case .success(let response):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api scroll trace done id=\(debugID)")
                    self?.sendJSONObject(response, contentType: "application/json; charset=utf-8", status: .ok, on: connection)
                case .failure(let error):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api scroll trace fail id=\(debugID) error=\(error.localizedDescription)")
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

        if request.path == "/api/v1/dark-reader" {
            BrowserDebugLogging.log("[wkdomains-debug] local-api dark-reader start id=\(debugID)")
            dataReader.readDarkReaderStatus { [weak self] result in
                switch result {
                case .success(let response):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api dark-reader done id=\(debugID)")
                    self?.sendJSONObject(response, contentType: "application/json; charset=utf-8", status: .ok, on: connection)
                case .failure(let error):
                    BrowserDebugLogging.log("[wkdomains-debug] local-api dark-reader fail id=\(debugID) error=\(error.localizedDescription)")
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

}
