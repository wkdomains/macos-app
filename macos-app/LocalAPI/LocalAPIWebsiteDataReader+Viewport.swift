//
//  LocalAPIWebsiteDataReader+Viewport.swift
//  macos-app
//

import AppKit
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

    func compareVisual(
        arguments: [String: Any],
        completion: @escaping (Result<VisualComparisonOutput, Error>) -> Void
    ) {
        do {
            let referenceURL = try visualURL(
                from: arguments,
                keys: ["referenceUrl", "referenceURL", "baselineUrl", "baselineURL"]
            )
            let currentURL = try visualURL(
                from: arguments,
                keys: ["currentUrl", "currentURL", "url"],
                fallback: browser.webView.url
            )
            let width = Self.positiveInt(arguments["width"]) ?? max(1, Int(browser.webView.bounds.width.rounded()))
            let height = Self.positiveInt(arguments["height"]) ?? max(1, Int(browser.webView.bounds.height.rounded()))
            let threshold = Self.thresholdValue(arguments["threshold"])
            let comparisonID = UUID().uuidString.lowercased()
            let rawName = (arguments["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = rawName?.isEmpty == false ? rawName! : "\(width)x\(height)"

            startCapture(
                url: referenceURL,
                name: "\(name)-reference",
                width: width,
                height: height,
                includeScreenshot: true
            ) { [weak self] referenceResult in
                guard let self else { return }

                switch referenceResult {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let reference):
                    self.startCapture(
                        url: currentURL,
                        name: "\(name)-current",
                        width: width,
                        height: height,
                        includeScreenshot: true
                    ) { currentResult in
                        switch currentResult {
                        case .failure(let error):
                            completion(.failure(error))
                        case .success(let current):
                            do {
                                let comparison = try Self.visualComparison(
                                    id: comparisonID,
                                    name: name,
                                    current: current,
                                    reference: reference,
                                    threshold: threshold
                                )
                                completion(.success(comparison))
                            } catch {
                                completion(.failure(error))
                            }
                        }
                    }
                }
            }
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

    private func visualURL(
        from arguments: [String: Any],
        keys: [String],
        fallback: URL? = nil
    ) throws -> URL {
        for key in keys {
            guard let rawURL = arguments[key] as? String,
                  !rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                continue
            }

            guard let url = resolvedNavigationURL(from: rawURL) else {
                throw InspectionError.invalidNavigationURL
            }

            return url
        }

        if let fallback {
            return fallback
        }

        throw InspectionError.invalidVisualComparisonRequest
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

    private struct RGBAImage {
        let width: Int
        let height: Int
        let pixels: [UInt8]
    }

    private static func thresholdValue(_ value: Any?) -> Int {
        let raw: Int?
        switch value {
        case let value as Int:
            raw = value
        case let value as Double:
            raw = Int(value.rounded())
        case let value as NSNumber:
            raw = value.intValue
        case let value as String:
            raw = Int(value)
        default:
            raw = nil
        }

        return min(255, max(0, raw ?? 8))
    }

    private static func visualComparison(
        id: String,
        name: String,
        current: ViewportCaptureOutput,
        reference: ViewportCaptureOutput,
        threshold: Int
    ) throws -> VisualComparisonOutput {
        guard let currentPNG = current.screenshotPNG,
              let referencePNG = reference.screenshotPNG
        else {
            throw InspectionError.captureFailed
        }

        let diff = try compareScreenshots(
            currentPNG: currentPNG,
            referencePNG: referencePNG,
            threshold: threshold
        )

        return VisualComparisonOutput(
            id: id,
            name: name,
            current: current,
            reference: reference,
            metrics: diff.metrics,
            diffPNG: diff.diffPNG
        )
    }

    private static func compareScreenshots(
        currentPNG: Data,
        referencePNG: Data,
        threshold: Int
    ) throws -> (metrics: [String: Any], diffPNG: Data?) {
        guard let current = rgbaImage(from: currentPNG),
              let reference = rgbaImage(from: referencePNG)
        else {
            throw InspectionError.captureFailed
        }

        let width = max(current.width, reference.width)
        let height = max(current.height, reference.height)
        let totalPixels = max(1, width * height)
        var diffPixels = [UInt8](repeating: 255, count: totalPixels * 4)
        var changedPixels = 0
        var maxChannelDelta = 0
        var channelDeltaTotal: Int64 = 0
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        let tileColumns = min(12, max(1, width / 96))
        let tileRows = min(12, max(1, height / 96))
        var tileChangedPixels = [Int](repeating: 0, count: tileColumns * tileRows)
        var tileTotalPixels = [Int](repeating: 0, count: tileColumns * tileRows)

        for y in 0..<height {
            for x in 0..<width {
                let currentPixel = pixel(in: current, x: x, y: y)
                let referencePixel = pixel(in: reference, x: x, y: y)
                let outputIndex = (y * width + x) * 4
                let tileX = min(tileColumns - 1, x * tileColumns / width)
                let tileY = min(tileRows - 1, y * tileRows / height)
                let tileIndex = tileY * tileColumns + tileX
                tileTotalPixels[tileIndex] += 1

                let channelDelta: Int
                if let currentPixel, let referencePixel {
                    channelDelta = max(
                        abs(Int(currentPixel.r) - Int(referencePixel.r)),
                        abs(Int(currentPixel.g) - Int(referencePixel.g)),
                        abs(Int(currentPixel.b) - Int(referencePixel.b)),
                        abs(Int(currentPixel.a) - Int(referencePixel.a))
                    )
                } else {
                    channelDelta = 255
                }

                channelDeltaTotal += Int64(channelDelta)
                maxChannelDelta = max(maxChannelDelta, channelDelta)

                let changed = channelDelta > threshold
                if changed {
                    changedPixels += 1
                    tileChangedPixels[tileIndex] += 1
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                    diffPixels[outputIndex] = 230
                    diffPixels[outputIndex + 1] = 37
                    diffPixels[outputIndex + 2] = 66
                    diffPixels[outputIndex + 3] = 255
                } else if let currentPixel {
                    diffPixels[outputIndex] = UInt8((Int(currentPixel.r) * 35 + 255 * 65) / 100)
                    diffPixels[outputIndex + 1] = UInt8((Int(currentPixel.g) * 35 + 255 * 65) / 100)
                    diffPixels[outputIndex + 2] = UInt8((Int(currentPixel.b) * 35 + 255 * 65) / 100)
                    diffPixels[outputIndex + 3] = 255
                }
            }
        }

        let changedPercent = (Double(changedPixels) / Double(totalPixels)) * 100
        let boundingBox: Any = changedPixels > 0
            ? [
                "x": minX,
                "y": minY,
                "width": maxX - minX + 1,
                "height": maxY - minY + 1
            ]
            : NSNull()
        let regions = changedRegions(
            tileChangedPixels: tileChangedPixels,
            tileTotalPixels: tileTotalPixels,
            tileColumns: tileColumns,
            tileRows: tileRows,
            width: width,
            height: height
        )

        let metrics: [String: Any] = [
            "threshold": threshold,
            "width": width,
            "height": height,
            "currentSize": [
                "width": current.width,
                "height": current.height
            ],
            "referenceSize": [
                "width": reference.width,
                "height": reference.height
            ],
            "sizeMismatch": current.width != reference.width || current.height != reference.height,
            "totalPixels": totalPixels,
            "changedPixels": changedPixels,
            "changedPercent": rounded(changedPercent, places: 4),
            "maxChannelDelta": maxChannelDelta,
            "averageChannelDelta": rounded(Double(channelDeltaTotal) / Double(totalPixels), places: 2),
            "boundingBox": boundingBox,
            "regions": regions
        ]

        return (
            metrics: metrics,
            diffPNG: pngData(fromRGBA: diffPixels, width: width, height: height)
        )
    }

    private static func changedRegions(
        tileChangedPixels: [Int],
        tileTotalPixels: [Int],
        tileColumns: Int,
        tileRows: Int,
        width: Int,
        height: Int
    ) -> [[String: Any]] {
        var regions: [[String: Any]] = []

        for tileY in 0..<tileRows {
            for tileX in 0..<tileColumns {
                let index = tileY * tileColumns + tileX
                let changed = tileChangedPixels[index]
                guard changed > 0 else { continue }

                let total = max(1, tileTotalPixels[index])
                let startX = tileX * width / tileColumns
                let endX = (tileX + 1) * width / tileColumns
                let startY = tileY * height / tileRows
                let endY = (tileY + 1) * height / tileRows

                regions.append([
                    "x": startX,
                    "y": startY,
                    "width": max(1, endX - startX),
                    "height": max(1, endY - startY),
                    "changedPixels": changed,
                    "changedPercent": rounded((Double(changed) / Double(total)) * 100, places: 2)
                ])
            }
        }

        return regions.sorted {
            (($0["changedPercent"] as? Double) ?? 0) > (($1["changedPercent"] as? Double) ?? 0)
        }.prefix(12).map { $0 }
    }

    private static func rgbaImage(from pngData: Data) -> RGBAImage? {
        guard let image = NSImage(data: pngData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            return nil
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else {
                return false
            }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard rendered else {
            return nil
        }

        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    private static func pixel(in image: RGBAImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard x >= 0, y >= 0, x < image.width, y < image.height else {
            return nil
        }

        let index = (y * image.width + x) * 4
        return (
            image.pixels[index],
            image.pixels[index + 1],
            image.pixels[index + 2],
            image.pixels[index + 3]
        )
    }

    private static func pngData(fromRGBA pixels: [UInt8], width: Int, height: Int) -> Data? {
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              )
        else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func rounded(_ value: Double, places: Int) -> Double {
        let multiplier = pow(10, Double(places))
        return (value * multiplier).rounded() / multiplier
    }
}
