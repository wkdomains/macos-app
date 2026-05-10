//
//  LocalAPIWebsiteDataReader+Viewport.swift
//  macos-app
//

import CoreGraphics
import Foundation
@preconcurrency import WebKit

extension WebsiteDataReader {
    private struct CaptureViewportSpec {
        let name: String
        let width: Int
        let height: Int
    }

    func readViewport() -> [String: Any] {
        let page = readPage()
        return [
            "mode": page.viewportMode,
            "width": page.viewportWidth,
            "height": page.viewportHeight,
            "availableModes": BrowserViewportMode.allCases.map { mode in
                [
                    "mode": mode.rawValue,
                    "width": Self.json(mode.width.map { Int($0.rounded()) }),
                    "label": mode.accessibilityLabel
                ] as [String: Any]
            },
            "note": "The visible browser supports desktop, mobileLarge, and mobileSmall. Exact width/height captures are available through /api/v1/capture and /api/v1/qa/viewports."
        ]
    }

    func setViewport(arguments: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        let mode: BrowserViewportMode?
        let previousMode = browser.viewportMode
        let previousWidth = browser.webView.bounds.width

        if let rawMode = arguments["mode"] as? String {
            mode = BrowserViewportMode(rawValue: rawMode)
        } else if let width = Self.positiveInt(arguments["width"]) {
            switch width {
            case 390:
                mode = .mobileSmall
            case 700:
                mode = .mobileLarge
            default:
                mode = .desktop
            }
        } else {
            mode = nil
        }

        guard let mode else {
            completion(.failure(InspectionError.invalidViewportRequest))
            return
        }

        guard previousMode != mode else {
            completion(.success(readViewport()))
            return
        }

        browser.setViewportMode(mode)
        waitForViewportLayout(mode: mode, previousWidth: previousWidth, attempts: 0, completion: completion)
    }

    func captureViewport(
        arguments: [String: Any],
        completion: @escaping (Result<ViewportCaptureOutput, Error>) -> Void
    ) {
        do {
            let url = try captureURL(from: arguments)
            let width = Self.positiveInt(arguments["width"]) ?? max(1, Int(browser.webView.bounds.width.rounded()))
            let height = Self.positiveInt(arguments["height"]) ?? max(1, Int(browser.webView.bounds.height.rounded()))
            let name = (arguments["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let includeScreenshot = arguments["includeScreenshot"] as? Bool ?? true

            guard width > 0, height > 0 else {
                throw InspectionError.invalidViewportRequest
            }

            startCapture(
                url: url,
                name: name?.isEmpty == false ? name! : "\(width)x\(height)",
                width: width,
                height: height,
                includeScreenshot: includeScreenshot,
                completion: completion
            )
        } catch {
            completion(.failure(error))
        }
    }

    func captureViewports(
        arguments: [String: Any],
        completion: @escaping (Result<[ViewportCaptureOutput], Error>) -> Void
    ) {
        do {
            let url = try captureURL(from: arguments)
            let specs = try viewportSpecs(from: arguments)
            let includeScreenshot = arguments["includeScreenshot"] as? Bool ?? true
            var outputs: [ViewportCaptureOutput] = []

            func run(index: Int) {
                if index >= specs.count {
                    completion(.success(outputs))
                    return
                }

                let spec = specs[index]
                startCapture(
                    url: url,
                    name: spec.name,
                    width: spec.width,
                    height: spec.height,
                    includeScreenshot: includeScreenshot
                ) { result in
                    switch result {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let output):
                        outputs.append(output)
                        run(index: index + 1)
                    }
                }
            }

            run(index: 0)
        } catch {
            completion(.failure(error))
        }
    }

    private func waitForViewportLayout(
        mode: BrowserViewportMode,
        previousWidth: CGFloat,
        attempts: Int,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        let width = browser.webView.bounds.width
        let settled: Bool

        if let targetWidth = mode.width {
            settled = abs(width - targetWidth) <= 1
        } else {
            settled = attempts >= 2 && abs(width - previousWidth) > 1
        }

        if settled || attempts >= 20 {
            completion(.success(readViewport()))
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.waitForViewportLayout(
                mode: mode,
                previousWidth: previousWidth,
                attempts: attempts + 1,
                completion: completion
            )
        }
    }

    private func captureURL(from arguments: [String: Any]) throws -> URL {
        if let rawURL = arguments["url"] as? String {
            guard let url = resolvedNavigationURL(from: rawURL) else {
                throw InspectionError.invalidNavigationURL
            }

            return url
        }

        guard let url = browser.webView.url else {
            throw InspectionError.noPageLoaded
        }

        return url
    }

    private func viewportSpecs(from arguments: [String: Any]) throws -> [CaptureViewportSpec] {
        guard let rawViewports = arguments["viewports"] as? [Any] else {
            return [
                CaptureViewportSpec(name: "mobile-390", width: 390, height: 844),
                CaptureViewportSpec(name: "tablet-768", width: 768, height: 1024),
                CaptureViewportSpec(name: "desktop-1280", width: 1280, height: 800),
                CaptureViewportSpec(name: "desktop-1440", width: 1440, height: 900)
            ]
        }

        let specs = rawViewports.compactMap { raw -> CaptureViewportSpec? in
            guard let viewport = raw as? [String: Any],
                  let width = Self.positiveInt(viewport["width"]),
                  let height = Self.positiveInt(viewport["height"])
            else {
                return nil
            }

            let rawName = (viewport["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return CaptureViewportSpec(
                name: rawName?.isEmpty == false ? rawName! : "\(width)x\(height)",
                width: width,
                height: height
            )
        }

        guard specs.count == rawViewports.count, !specs.isEmpty else {
            throw InspectionError.invalidViewportRequest
        }

        return specs
    }

    private func startCapture(
        url: URL,
        name: String,
        width: Int,
        height: Int,
        includeScreenshot: Bool,
        completion: @escaping (Result<ViewportCaptureOutput, Error>) -> Void
    ) {
        let id = UUID().uuidString.lowercased()
        let session = WebKitViewportCaptureSession(
            id: id,
            name: name,
            url: url,
            width: width,
            height: height,
            dataStore: browser.webView.configuration.websiteDataStore,
            includeScreenshot: includeScreenshot
        ) { [weak self] result in
            self?.viewportCaptureSessions.removeValue(forKey: id)
            completion(result)
        }

        viewportCaptureSessions[id] = session
        session.start()
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        switch value {
        case let value as Int where value > 0:
            return value
        case let value as Double where value > 0:
            return Int(value.rounded())
        case let value as NSNumber where value.intValue > 0:
            return value.intValue
        case let value as String:
            return Int(value).flatMap { $0 > 0 ? $0 : nil }
        default:
            return nil
        }
    }
}
