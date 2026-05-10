//
//  LocalAPIWebsiteDataReader+Scenario.swift
//  macos-app
//

import Foundation

extension WebsiteDataReader {
    func runScenario(arguments: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let rawSteps = arguments["steps"] as? [[String: Any]], !rawSteps.isEmpty else {
            completion(.failure(InspectionError.invalidScenarioRequest))
            return
        }

        let name = Self.stringValue(arguments["name"]) ?? "scenario"
        let stopOnError = Self.boolValue(arguments["stopOnError"]) ?? true
        let startedAt = Date()
        var outputs: [[String: Any]] = []

        func finish(ok: Bool) {
            completion(
                .success(
                    [
                        "ok": ok,
                        "name": name,
                        "steps": outputs,
                        "elapsedMilliseconds": Int(Date().timeIntervalSince(startedAt) * 1000)
                    ]
                )
            )
        }

        func appendFailure(index: Int, step: [String: Any], error: Error) {
            outputs.append(
                [
                    "ok": false,
                    "index": index,
                    "id": Self.json(Self.stringValue(step["id"])),
                    "op": Self.operationName(for: step),
                    "error": error.localizedDescription,
                    "elapsedMilliseconds": Int(Date().timeIntervalSince(startedAt) * 1000)
                ]
            )
        }

        func runStep(at index: Int) {
            guard rawSteps.indices.contains(index) else {
                finish(ok: !outputs.contains { ($0["ok"] as? Bool) == false })
                return
            }

            let step = rawSteps[index]
            let stepStartedAt = Date()
            let op = Self.operationName(for: step)

            func record(_ output: Any, ok: Bool = true) {
                outputs.append(
                    [
                        "ok": ok,
                        "index": index,
                        "id": Self.json(Self.stringValue(step["id"])),
                        "op": op,
                        "elapsedMilliseconds": Int(Date().timeIntervalSince(stepStartedAt) * 1000),
                        "result": output
                    ]
                )
                runStep(at: index + 1)
            }

            func fail(_ error: Error) {
                appendFailure(index: index, step: step, error: error)
                if stopOnError {
                    finish(ok: false)
                } else {
                    runStep(at: index + 1)
                }
            }

            switch op {
            case "navigate":
                guard let url = Self.stringValue(step["url"]) else {
                    fail(InspectionError.invalidNavigationRequest)
                    return
                }

                navigate(to: url, mode: Self.stringValue(step["mode"])) { result in
                    switch result {
                    case .success(let response):
                        record(response)
                    case .failure(let error):
                        fail(error)
                    }
                }
            case "action":
                let actionArguments = Self.actionArguments(from: step)
                performAction(arguments: actionArguments) { result in
                    switch result {
                    case .success(let response):
                        record(response)
                    case .failure(let error):
                        fail(error)
                    }
                }
            case "page":
                record(Self.encodableObject(readPage()))
            case "snapshot":
                readSnapshot { result in
                    switch result {
                    case .success(let response):
                        record(response)
                    case .failure(let error):
                        fail(error)
                    }
                }
            case "observe":
                readObserve { result in
                    switch result {
                    case .success(let response):
                        record(response)
                    case .failure(let error):
                        fail(error)
                    }
                }
            case "dom":
                readDOM { result in
                    switch result {
                    case .success(let response):
                        record(response)
                    case .failure(let error):
                        fail(error)
                    }
                }
            case "layout":
                readLayoutDiagnostics { result in
                    switch result {
                    case .success(let response):
                        record(response)
                    case .failure(let error):
                        fail(error)
                    }
                }
            case "console":
                record(Self.encodableObject(readConsoleMessages()))
            case "xhr":
                switch readXHRRequestsForCurrentPage() {
                case .success(let response):
                    record(Self.encodableObject(response))
                case .failure(let error):
                    fail(error)
                }
            case "sleep":
                let milliseconds = min(max(Self.intValue(step["milliseconds"]) ?? Self.intValue(step["ms"]) ?? 250, 0), 5_000)
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                    record(["milliseconds": milliseconds])
                }
            default:
                fail(InspectionError.invalidScenarioRequest)
            }
        }

        runStep(at: 0)
    }

    private static func operationName(for step: [String: Any]) -> String {
        if let kind = stringValue(step["kind"]) ?? stringValue(step["op"]) ?? stringValue(step["step"]) {
            return kind.lowercased()
        }

        let type = stringValue(step["type"])?.lowercased()
        switch type {
        case "click", "fill", "setvalue", "clear", "select", "submit", "press", "focus":
            return "action"
        default:
            return type ?? ""
        }
    }

    private static func actionArguments(from step: [String: Any]) -> [String: Any] {
        var output = step
        output.removeValue(forKey: "id")
        output.removeValue(forKey: "kind")
        output.removeValue(forKey: "op")
        output.removeValue(forKey: "step")

        if let action = stringValue(step["action"]) {
            output["type"] = action
            output.removeValue(forKey: "action")
        }

        return output
    }

    private static func encodableObject<T: Encodable>(_ value: T) -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return String(describing: value)
        }

        return object
    }
}
