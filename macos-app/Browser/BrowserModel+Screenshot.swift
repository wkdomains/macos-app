//
//  BrowserModel+Screenshot.swift
//  macos-app
//

import AppKit
import Foundation
import WebKit

extension BrowserModel {
    func currentVisiblePageScreenshotPNG(completion: @escaping (Result<Data, Error>) -> Void) {
        if let screenshotPNG,
           screenshotCapturedVersion == screenshotDirtyVersion,
           !webView.isLoading
        {
            completion(.success(screenshotPNG))
            return
        }

        guard hasAttemptedNavigation, webView.url != nil else {
            completion(.failure(ScreenshotError.noPageLoaded))
            return
        }

        let waiterID = UUID()
        screenshotWaiters[waiterID] = completion

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let completion = self?.screenshotWaiters.removeValue(forKey: waiterID) else { return }
            completion(.failure(ScreenshotError.timedOut))
        }

        guard !webView.isLoading else { return }
        scheduleScreenshotCapture(after: 0)
    }

    func resetScreenshotForNavigation() {
        screenshotNavigationGeneration += 1
        screenshotDirtyVersion += 1
        screenshotCapturedVersion = -1
        screenshotPNG = nil
        screenshotRenderTask?.cancel()
        screenshotRenderTask = nil
    }

    func markScreenshotDirty(scheduleAfter delay: TimeInterval) {
        guard hasAttemptedNavigation, webView.url != nil else { return }

        screenshotDirtyVersion += 1

        guard !screenshotWaiters.isEmpty else { return }
        guard !webView.isLoading else { return }
        scheduleScreenshotCapture(after: delay)
    }

    private func scheduleScreenshotCapture(after delay: TimeInterval) {
        guard hasAttemptedNavigation, webView.url != nil else { return }

        screenshotRenderTask?.cancel()
        let generation = screenshotNavigationGeneration
        let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)

        screenshotRenderTask = Task { @MainActor [weak self] in
            if nanoseconds > 0 {
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled,
                  let self,
                  self.screenshotNavigationGeneration == generation
            else {
                return
            }

            self.captureVisiblePageScreenshot(generation: generation)
        }
    }

    private func captureVisiblePageScreenshot(generation: Int) {
        guard !screenshotIsRendering else { return }
        guard !webView.isLoading else { return }
        guard webView.bounds.width >= 1, webView.bounds.height >= 1 else {
            finishScreenshotWaiters(with: .failure(ScreenshotError.webViewNotVisible))
            return
        }

        screenshotIsRendering = true
        let capturedVersion = screenshotDirtyVersion
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds

        webView.takeSnapshot(with: configuration) { [weak self] image, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.screenshotIsRendering = false

                guard self.screenshotNavigationGeneration == generation else {
                    if !self.webView.isLoading {
                        self.scheduleScreenshotCapture(after: 0.2)
                    }
                    return
                }

                if let error {
                    self.finishScreenshotWaiters(with: .failure(error))
                    return
                }

                guard let image,
                      let pngData = Self.pngData(from: image)
                else {
                    self.finishScreenshotWaiters(with: .failure(ScreenshotError.pngEncodingFailed))
                    return
                }

                self.screenshotPNG = pngData
                self.screenshotCapturedVersion = capturedVersion

                if self.screenshotCapturedVersion == self.screenshotDirtyVersion {
                    self.finishScreenshotWaiters(with: .success(pngData))
                } else {
                    self.scheduleScreenshotCapture(after: 0.15)
                }
            }
        }
    }

    func finishScreenshotWaiters(with result: Result<Data, Error>) {
        let waiters = Array(screenshotWaiters.values)
        screenshotWaiters.removeAll()

        for completion in waiters {
            completion(result)
        }
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}

private enum ScreenshotError: LocalizedError {
    case noPageLoaded
    case pngEncodingFailed
    case timedOut
    case webViewNotVisible

    var errorDescription: String? {
        switch self {
        case .noPageLoaded:
            return "No page is loaded."
        case .pngEncodingFailed:
            return "Could not encode the screenshot as PNG."
        case .timedOut:
            return "Timed out waiting for the screenshot to be rendered."
        case .webViewNotVisible:
            return "The web view is not visible."
        }
    }
}
