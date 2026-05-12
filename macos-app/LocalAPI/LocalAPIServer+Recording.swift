//
//  LocalAPIServer+Recording.swift
//  macos-app
//

import Foundation
@preconcurrency import Network

@MainActor
extension LocalAPIServer {
    func routeRecording(_ request: HTTPRequest, connection: NWConnection) {
        if request.method == "GET", request.path == "/api/v1/recording" {
            sendRecordingState(action: "status", on: connection)
            return
        }

        guard request.method == "POST" else {
            sendError(status: .methodNotAllowed, message: "Use GET for status or POST for recording control.", on: connection)
            return
        }

        guard request.originIsAllowed else {
            sendError(status: .badRequest, message: "Origin is not allowed.", on: connection)
            return
        }

        let action: String?
        if request.path == "/api/v1/recording" {
            action = jsonBody(from: request)?["action"] as? String
        } else {
            action = String(request.path.dropFirst("/api/v1/recording/".count))
        }

        guard let action else {
            sendError(status: .badRequest, message: "Provide a recording action: start, pause, resume, or stop.", on: connection)
            return
        }

        switch action.lowercased() {
        case "start":
            screenRecorder.startRecording()
        case "pause":
            screenRecorder.pauseRecording()
        case "resume":
            screenRecorder.resumeRecording()
        case "stop":
            screenRecorder.stopRecording()
        default:
            sendError(status: .badRequest, message: "Unknown recording action: \(action).", on: connection)
            return
        }

        sendRecordingState(action: action.lowercased(), on: connection)
    }

    private func sendRecordingState(action: String, on connection: NWConnection) {
        var response = screenRecorder.apiState
        response["action"] = action
        sendJSONObject(response, contentType: "application/json; charset=utf-8", status: .ok, on: connection)
    }
}
