//
//  LocalAPIWebsiteDataReader+Action.swift
//  macos-app
//

import Foundation
@preconcurrency import WebKit

extension WebsiteDataReader {
    func performAction(arguments: [String: Any], completion: @escaping (Result<Any, Error>) -> Void) {
        guard BrowserModel.actionInspectionScript(arguments: arguments) != nil else {
            completion(.failure(InspectionError.invalidActionRequest))
            return
        }

        let runAction = { [weak self] in
            guard let self else { return }
            guard let script = BrowserModel.actionInspectionScript(arguments: arguments) else {
                completion(.failure(InspectionError.invalidActionRequest))
                return
            }

            let actionStartedAt = Date()
            self.evaluateJSONScript(script, label: "action") { result in
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let response):
                    let waitFor = self.waitArguments(from: arguments)
                    let actionSucceeded = (response as? [String: Any])?["ok"] as? Bool ?? true
                    guard actionSucceeded, let waitFor else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            completion(.success(response))
                        }
                        return
                    }

                    self.waitForCondition(waitFor, startedAt: actionStartedAt) { waitResult in
                        switch waitResult {
                        case .failure(let error):
                            completion(.failure(error))
                        case .success(let waitResponse):
                            var output = response as? [String: Any] ?? ["actionResult": response]
                            output["wait"] = waitResponse
                            completion(.success(output))
                        }
                    }
                }
            }
        }

        let ref = (arguments["ref"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !ref.isEmpty else {
            runAction()
            return
        }

        readSnapshot { snapshotResult in
            switch snapshotResult {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                runAction()
            }
        }
    }

    private func waitArguments(from arguments: [String: Any]) -> [String: Any]? {
        if let waitFor = arguments["waitFor"] as? [String: Any] {
            return waitFor
        }

        if let wait = arguments["wait"] as? [String: Any] {
            return wait
        }

        return nil
    }

    private func waitForCondition(
        _ waitFor: [String: Any],
        startedAt: Date,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard BrowserModel.waitInspectionScript(arguments: waitFor) != nil else {
            completion(.failure(InspectionError.invalidActionRequest))
            return
        }

        let timeout = waitTimeout(from: waitFor)
        var lastResponse: [String: Any] = [:]

        func poll() {
            guard let script = BrowserModel.waitInspectionScript(arguments: waitFor) else {
                completion(.failure(InspectionError.invalidActionRequest))
                return
            }

            evaluateJSONScript(script, label: "wait") { result in
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let response):
                    var dictionary = response as? [String: Any] ?? ["value": response]
                    let domMatched = dictionary["ok"] as? Bool == true

                    if domMatched, var xhrWait = self.xhrWaitResponse(from: waitFor, startedAt: startedAt) {
                        if xhrWait["ok"] as? Bool == true {
                            dictionary["xhr"] = xhrWait
                        } else {
                            xhrWait["url"] = dictionary["url"]
                            xhrWait["title"] = dictionary["title"]
                            xhrWait["readyState"] = dictionary["readyState"]
                            dictionary = xhrWait
                        }
                    }

                    lastResponse = dictionary
                    if dictionary["ok"] as? Bool == true {
                        dictionary["elapsedMilliseconds"] = Int(Date().timeIntervalSince(startedAt) * 1000)
                        completion(.success(dictionary))
                        return
                    }

                    if Date().timeIntervalSince(startedAt) >= timeout {
                        var timeoutDictionary = lastResponse.isEmpty ? dictionary : lastResponse
                        timeoutDictionary["timedOut"] = true
                        timeoutDictionary["elapsedMilliseconds"] = Int(Date().timeIntervalSince(startedAt) * 1000)
                        completion(.success(timeoutDictionary))
                        return
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        poll()
                    }
                }
            }
        }

        poll()
    }

    private func xhrWaitResponse(from waitFor: [String: Any], startedAt: Date) -> [String: Any]? {
        let rawXHR: [String: Any]?
        if let xhr = waitFor["xhr"] as? [String: Any] {
            rawXHR = xhr
        } else if waitFor["xhrURLContains"] != nil
                    || waitFor["xhrUrlContains"] != nil
                    || waitFor["xhrStatus"] != nil
                    || waitFor["xhrMethod"] != nil
                    || waitFor["xhrCompleted"] != nil
        {
            rawXHR = waitFor
        } else {
            rawXHR = nil
        }

        guard let rawXHR else {
            return nil
        }

        let urlContains = Self.stringValue(rawXHR["urlContains"])
            ?? Self.stringValue(rawXHR["url"])
            ?? Self.stringValue(rawXHR["xhrURLContains"])
            ?? Self.stringValue(rawXHR["xhrUrlContains"])
        let method = (Self.stringValue(rawXHR["method"]) ?? Self.stringValue(rawXHR["xhrMethod"]))?.uppercased()
        let status = Self.intValue(rawXHR["status"]) ?? Self.intValue(rawXHR["xhrStatus"])
        let completed = Self.boolValue(rawXHR["completed"]) ?? Self.boolValue(rawXHR["xhrCompleted"]) ?? true
        let responseBodyContains = Self.stringValue(rawXHR["responseBodyContains"])
            ?? Self.stringValue(rawXHR["bodyContains"])
            ?? Self.stringValue(rawXHR["xhrResponseBodyContains"])
        let jsonShapeContains = Self.stringValue(rawXHR["jsonShapeContains"])
            ?? Self.stringValue(rawXHR["xhrJsonShapeContains"])

        let pageHost = browser.webView.url?.host?.lowercased()
        let candidateRecords = browser.xhrRecords
            .filter { record in
                record.startedAt >= startedAt
            }
            .filter { record in
                guard let pageHost else { return true }
                guard let host = record.host ?? URL(string: record.url)?.host?.lowercased() else { return true }
                return BrowserModel.host(host, matches: pageHost)
            }

        let matches = candidateRecords.filter { record in
            if let urlContains, !record.url.localizedCaseInsensitiveContains(urlContains) {
                return false
            }

            if let method, record.method.uppercased() != method {
                return false
            }

            if completed, record.completedAt == nil {
                return false
            }

            if let status, record.status != status {
                return false
            }

            if let responseBodyContains,
               !(record.responseBodyPreview ?? "").localizedCaseInsensitiveContains(responseBodyContains)
            {
                return false
            }

            if let jsonShapeContains,
               !(record.jsonShape ?? "").localizedCaseInsensitiveContains(jsonShapeContains)
            {
                return false
            }

            return true
        }

        let samples = candidateRecords.suffix(8).map(Self.xhrWaitDictionary(from:))
        guard let match = matches.last else {
            return [
                "ok": false,
                "reason": "xhr",
                "xhr": [
                    "expected": [
                        "urlContains": Self.json(urlContains),
                        "method": Self.json(method),
                        "status": Self.json(status),
                        "completed": completed,
                        "responseBodyContains": Self.json(responseBodyContains),
                        "jsonShapeContains": Self.json(jsonShapeContains)
                    ],
                    "observedCount": candidateRecords.count,
                    "recent": samples
                ]
            ]
        }

        return [
            "ok": true,
            "matched": ["xhr"],
            "xhr": Self.xhrWaitDictionary(from: match)
        ]
    }

    private func waitTimeout(from waitFor: [String: Any]) -> TimeInterval {
        if let timeoutMilliseconds = waitFor["timeoutMs"] as? Double {
            return min(max(timeoutMilliseconds / 1000, 0.2), 20)
        }

        if let timeoutMilliseconds = waitFor["timeoutMs"] as? Int {
            return min(max(Double(timeoutMilliseconds) / 1000, 0.2), 20)
        }

        if let timeoutSeconds = waitFor["timeoutSeconds"] as? Double {
            return min(max(timeoutSeconds, 0.2), 20)
        }

        return 5
    }

    static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as Double:
            return Int(value.rounded())
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private static func xhrWaitDictionary(from record: XHRRequestRecord) -> [String: Any] {
        [
            "id": record.id,
            "kind": record.kind,
            "method": record.method,
            "url": record.url,
            "status": Self.json(record.status),
            "completedAt": Self.json(record.completedAt.map(Self.iso8601Formatter.string(from:))),
            "responseBytes": Self.json(record.responseBytes),
            "jsonShape": Self.json(record.jsonShape),
            "responseBodyPreview": Self.json(record.responseBodyPreview),
            "error": Self.json(record.error)
        ]
    }
}
