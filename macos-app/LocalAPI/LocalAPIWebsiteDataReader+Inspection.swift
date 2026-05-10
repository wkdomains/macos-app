//
//  LocalAPIWebsiteDataReader+Inspection.swift
//  macos-app
//

import Foundation
@preconcurrency import WebKit

extension WebsiteDataReader {
    func readScreenshot(completion: @escaping (Result<Data, Error>) -> Void) {
        browser.currentVisiblePageScreenshotPNG(completion: completion)
    }

    func readLayoutDiagnostics(completion: @escaping (Result<Any, Error>) -> Void) {
        evaluateJSONScript(BrowserModel.layoutDiagnosticsInspectionScript, label: "layout", completion: completion)
    }

    func readElementXRay(ref rawRef: String, completion: @escaping (Result<Any, Error>) -> Void) {
        let ref = rawRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ref.hasPrefix("@e"),
              BrowserModel.elementXRayInspectionScript(ref: ref) != nil
        else {
            completion(.failure(InspectionError.invalidElementRef))
            return
        }

        readSnapshot { [weak self] snapshotResult in
            guard let self else { return }

            switch snapshotResult {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                guard let script = BrowserModel.elementXRayInspectionScript(ref: ref) else {
                    completion(.failure(InspectionError.invalidElementRef))
                    return
                }

                self.evaluateJSONScript(script, label: "element-\(ref)", completion: completion)
            }
        }
    }
}
