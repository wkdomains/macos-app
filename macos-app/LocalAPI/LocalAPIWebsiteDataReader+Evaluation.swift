//
//  LocalAPIWebsiteDataReader+Evaluation.swift
//  macos-app
//

import Foundation
@preconcurrency import WebKit

extension WebsiteDataReader {
    func evaluateJSONScript(_ script: String, label: String, completion: @escaping (Result<Any, Error>) -> Void) {
        guard browser.webView.url != nil else {
            BrowserDebugLogging.log("[wkdomains-debug] local-api eval \(label) fail no-page")
            completion(.failure(InspectionError.noPageLoaded))
            return
        }

        let startedAt = Date()
        let startURL = browser.webView.url?.absoluteString ?? "nil"
        BrowserDebugLogging.log("[wkdomains-debug] local-api eval \(label) start \(pageStateDescription()) scriptBytes=\(script.utf8.count)")

        var didFinish = false
        let finish: (Result<Any, Error>) -> Void = { result in
            guard !didFinish else { return }
            didFinish = true
            completion(result)
        }

        let slowWarning = DispatchWorkItem { [weak self] in
            guard let self else { return }
            BrowserDebugLogging.log(
                "[wkdomains-debug] local-api eval \(label) slow elapsed=\(Self.formatElapsed(since: startedAt)) startURL=\(startURL) \(self.pageStateDescription())"
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: slowWarning)

        let timeout = DispatchWorkItem {
            slowWarning.cancel()
            BrowserDebugLogging.log("[wkdomains-debug] local-api eval \(label) timeout elapsed=\(Self.formatElapsed(since: startedAt)) startURL=\(startURL)")
            finish(.failure(InspectionError.evaluationTimedOut(label)))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)

        browser.webView.evaluateJavaScript(script) { value, error in
            Task { @MainActor in
                slowWarning.cancel()
                timeout.cancel()
                if let error {
                    BrowserDebugLogging.log("[wkdomains-debug] local-api eval \(label) fail elapsed=\(Self.formatElapsed(since: startedAt)) error=\(error.localizedDescription) \(self.pageStateDescription())")
                    finish(.failure(error))
                    return
                }

                guard let json = value as? String,
                      let data = json.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data)
                else {
                    BrowserDebugLogging.log("[wkdomains-debug] local-api eval \(label) decode-fail elapsed=\(Self.formatElapsed(since: startedAt)) valueType=\(String(describing: type(of: value))) \(self.pageStateDescription())")
                    finish(.failure(InspectionError.couldNotDecodePageJSON))
                    return
                }

                BrowserDebugLogging.log("[wkdomains-debug] local-api eval \(label) done elapsed=\(Self.formatElapsed(since: startedAt)) jsonBytes=\(data.count) objectType=\(String(describing: type(of: object))) \(self.pageStateDescription())")
                finish(.success(object))
            }
        }
    }

    private func pageStateDescription() -> String {
        "url=\(browser.webView.url?.absoluteString ?? "nil") loading=\(browser.webView.isLoading) progress=\(String(format: "%.3f", browser.webView.estimatedProgress)) title=\(browser.webView.title ?? "nil")"
    }

    private static func formatElapsed(since startedAt: Date) -> String {
        String(format: "%.3fs", Date().timeIntervalSince(startedAt))
    }

    static func originString(from url: URL) -> String {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port

        return components.url?.absoluteString ?? url.absoluteString
    }

    static func dictionary(from request: BotTerminalRequest) -> [String: Any] {
        [
            "id": request.id.uuidString,
            "createdAt": iso8601Formatter.string(from: request.createdAt),
            "currentURL": request.currentURL,
            "pageHost": request.pageHost,
            "domain": request.domain,
            "llmsURL": request.llmsURL,
            "userAgent": request.userAgent,
            "prompt": request.prompt,
            "status": request.status
        ]
    }

    static func resourceCandidates(for domain: String) -> [URL] {
        [
            "/llms.txt",
            "/llms-full.txt",
            "/openapi.json",
            "/swagger.json",
            "/.well-known/openapi.json",
            "/.well-known/ai-plugin.json",
            "/.well-known/agent-card.json",
            "/sitemap.xml",
            "/robots.txt"
        ].compactMap { path in
            URL(string: "https://\(domain)\(path)")
        }
    }

    static func fetchResource(_ url: URL) async -> DomainResourceResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue(BotTerminalModel.llmsUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=0-8191", forHTTPHeaderField: "Range")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let contentType = httpResponse?.value(forHTTPHeaderField: "Content-Type")
            let contentLength = httpResponse?.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init)
            let isText = contentType?.lowercased().contains("text") == true
                || contentType?.lowercased().contains("json") == true
                || contentType?.lowercased().contains("xml") == true

            let preview: String?
            if isText, let text = String(data: data, encoding: .utf8) {
                preview = String(text.prefix(1200))
            } else {
                preview = nil
            }

            return DomainResourceResponse(
                url: url.absoluteString,
                path: url.path,
                status: httpResponse?.statusCode,
                found: (200..<400).contains(httpResponse?.statusCode ?? 0),
                contentType: contentType,
                contentLength: contentLength,
                sampledBytes: data.count,
                bodyPreview: preview,
                error: nil
            )
        } catch {
            return DomainResourceResponse(
                url: url.absoluteString,
                path: url.path,
                status: nil,
                found: false,
                contentType: nil,
                contentLength: nil,
                sampledBytes: 0,
                bodyPreview: nil,
                error: error.localizedDescription
            )
        }
    }

    static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
