//
//  BrowserModel.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import AppKit
import Combine
import Foundation
import WebKit

final class BrowserModel: NSObject, ObservableObject {
    @Published var addressText = ""
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var estimatedProgress = 0.0
    @Published private(set) var hasAttemptedNavigation = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSecurePage = false
    @Published private(set) var viewportMode: BrowserViewportMode = .desktop

    let webView: BrowserWKWebView
    let botTerminal = BotTerminalModel()

    private var observations: [NSKeyValueObservation] = []
    private var activePageHost: String?
    private var consoleRecords: [ConsoleMessageRecord] = []
    private var xhrRecords: [XHRRequestRecord] = []
    private var xhrRecordIndexesByID: [String: Int] = [:]
    private var screenshotPNG: Data?
    private var screenshotCapturedVersion = -1
    private var screenshotDirtyVersion = 0
    private var screenshotNavigationGeneration = 0
    private var screenshotIsRendering = false
    private var screenshotRenderTask: Task<Void, Never>?
    private var screenshotWaiters: [UUID: (Result<Data, Error>) -> Void] = [:]

    init(dataStore: WKWebsiteDataStore = .default()) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore

        webView = BrowserWKWebView(frame: .zero, configuration: configuration)

        super.init()

        webView.allowsBackForwardNavigationGestures = true
        webView.browserContextMenuDelegate = self
        webView.viewportSizeDidChange = { [weak self] in
            self?.markScreenshotDirty(scheduleAfter: 0.25)
        }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        installPageTrackingScripts(on: webView.configuration.userContentController)

        observations = [
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.estimatedProgress = webView.estimatedProgress
                }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.isLoading = webView.isLoading
                }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.canGoBack = webView.canGoBack
                }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.canGoForward = webView.canGoForward
                }
            },
            webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.syncAddress(from: webView)
                }
            }
        ]
    }

    func loadCurrentAddress() {
        let enteredAddress = addressText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = Self.normalizedURL(from: enteredAddress) else {
            errorMessage = "Enter a valid http or https address."
            return
        }

        hasAttemptedNavigation = true
        errorMessage = nil
        addressText = url.absoluteString
        isSecurePage = url.scheme?.lowercased() == "https"

        webView.load(URLRequest(url: url))
    }

    func goBack() {
        guard webView.canGoBack else { return }
        errorMessage = nil
        webView.goBack()
    }

    func goForward() {
        guard webView.canGoForward else { return }
        errorMessage = nil
        webView.goForward()
    }

    func reload() {
        guard hasAttemptedNavigation else { return }
        errorMessage = nil

        if webView.url == nil {
            loadCurrentAddress()
        } else {
            webView.reload()
        }
    }

    func stopLoading() {
        webView.stopLoading()
        isLoading = false
    }

    func clearCookiesForCurrentDomain() {
        guard let host = webView.url?.host?.lowercased() else { return }
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore

        cookieStore.getAllCookies { cookies in
            let matchingCookies = cookies.filter { cookie in
                let cookieDomain = cookie.domain
                    .lowercased()
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))

                return cookieDomain == host
                    || cookieDomain.hasSuffix(".\(host)")
                    || host.hasSuffix(".\(cookieDomain)")
            }

            for cookie in matchingCookies {
                cookieStore.delete(cookie)
            }
        }
    }

    func xhrRequests(for host: String) -> [XHRRequestRecord] {
        let normalizedHost = Self.normalizedHost(host)

        return xhrRecords.filter { record in
            guard let recordHost = record.host ?? URL(string: record.url)?.host else {
                return false
            }

            return Self.host(recordHost, matches: normalizedHost)
        }
    }

    func consoleMessages() -> [ConsoleMessageRecord] {
        consoleRecords
    }

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

    func setViewportMode(_ mode: BrowserViewportMode) {
        guard viewportMode != mode else { return }
        viewportMode = mode
        markScreenshotDirty(scheduleAfter: 0.35)
    }

    func requestLLMSSummary() {
        botTerminal.open(
            currentURL: webView.url,
            pageTitle: webView.title,
            viewportMode: viewportMode,
            xhrCount: xhrRecords.count
        )
    }

    func closeBotTerminal() {
        botTerminal.close()
    }

    func pendingBotRequests() -> [BotTerminalRequest] {
        botTerminal.pendingRequests()
    }

    func waitForPendingBotRequests(timeout: TimeInterval, completion: @escaping (_ requests: [BotTerminalRequest], _ timedOut: Bool) -> Void) {
        botTerminal.waitForPendingRequests(timeout: timeout, completion: completion)
    }

    func replyToBotRequest(id: UUID, summary: String) -> Bool {
        botTerminal.completeRequest(id: id, summary: summary)
    }

    func load(_ url: URL) {
        hasAttemptedNavigation = true
        errorMessage = nil
        addressText = url.absoluteString
        isSecurePage = url.scheme?.lowercased() == "https"
        resetXHRTracking(for: url)

        webView.load(URLRequest(url: url))
    }

    private func resetXHRTracking(for url: URL?) {
        activePageHost = url?.host?.lowercased()
        xhrRecords.removeAll(keepingCapacity: true)
        xhrRecordIndexesByID.removeAll(keepingCapacity: true)
        consoleRecords.removeAll(keepingCapacity: true)
    }

    private func recordConsoleMessage(_ message: [String: Any]) {
        let rawArguments = message["arguments"] as? [Any] ?? []
        let arguments = rawArguments.map { value in
            if let value = value as? String {
                return value
            }

            return String(describing: value)
        }

        let record = ConsoleMessageRecord(
            id: UUID(),
            level: message["level"] as? String ?? "log",
            message: message["message"] as? String ?? arguments.joined(separator: " "),
            arguments: arguments,
            pageURL: message["pageURL"] as? String,
            pageHost: (message["pageHost"] as? String)?.lowercased(),
            stack: message["stack"] as? String,
            createdAt: Date()
        )

        consoleRecords.append(record)
        if consoleRecords.count > 200 {
            consoleRecords.removeFirst(consoleRecords.count - 200)
        }
    }

    private func recordXHRMessage(_ message: [String: Any]) {
        guard let event = message["event"] as? String,
              let id = message["id"] as? String
        else {
            return
        }

        if event == "start" {
            guard let rawURL = message["url"] as? String,
                  let url = URL(string: rawURL)
            else {
                return
            }

            let record = XHRRequestRecord(
                id: id,
                kind: message["kind"] as? String ?? "xhr",
                method: (message["method"] as? String ?? "GET").uppercased(),
                url: url.absoluteString,
                host: url.host?.lowercased(),
                pageURL: message["pageURL"] as? String,
                pageHost: (message["pageHost"] as? String)?.lowercased(),
                startedAt: Date(),
                completedAt: nil,
                status: nil,
                responseURL: nil,
                responseBytes: nil,
                jsonType: nil,
                jsonItems: nil,
                jsonShape: nil,
                error: nil
            )

            xhrRecordIndexesByID[id] = xhrRecords.count
            xhrRecords.append(record)
            return
        }

        guard let index = xhrRecordIndexesByID[id],
              xhrRecords.indices.contains(index)
        else {
            return
        }

        xhrRecords[index].completedAt = Date()
        xhrRecords[index].status = Self.intValue(from: message["status"])
        xhrRecords[index].responseURL = message["responseURL"] as? String
        xhrRecords[index].responseBytes = Self.intValue(from: message["responseBytes"])
        xhrRecords[index].jsonType = message["jsonType"] as? String
        xhrRecords[index].jsonItems = Self.intValue(from: message["jsonItems"])
        xhrRecords[index].jsonShape = message["jsonShape"] as? String
        xhrRecords[index].error = message["error"] as? String

        markScreenshotDirty(scheduleAfter: 0.45)
    }

    private func syncAddress(from webView: WKWebView) {
        guard let url = webView.url else { return }

        addressText = url.absoluteString
        isSecurePage = url.scheme?.lowercased() == "https"
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        estimatedProgress = webView.estimatedProgress
        isLoading = webView.isLoading
    }

    private static func normalizedURL(from rawValue: String) -> URL? {
        guard !rawValue.isEmpty else { return nil }
        guard rawValue.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }

        var value = rawValue

        if !value.contains("://") {
            let lowercaseValue = value.lowercased()
            let isLocalHost = lowercaseValue == "localhost"
                || lowercaseValue.hasPrefix("localhost:")
                || lowercaseValue.hasPrefix("127.0.0.1")
                || lowercaseValue.hasPrefix("[::1]")
            value = "\(isLocalHost ? "http" : "https")://\(value)"
        }

        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil,
              let url = components.url
        else {
            return nil
        }

        return url
    }

    private static func normalizedHost(_ host: String) -> String {
        host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func host(_ host: String, matches requestedHost: String) -> Bool {
        let host = normalizedHost(host)

        return host == requestedHost
            || host.hasSuffix(".\(requestedHost)")
            || requestedHost.hasSuffix(".\(host)")
    }

    private static func intValue(from value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return nil
    }

    private func installPageTrackingScripts(on userContentController: WKUserContentController) {
        userContentController.add(self, name: "wkdomainsXHR")
        userContentController.add(self, name: "wkdomainsRender")
        userContentController.add(self, name: "wkdomainsConsole")
        userContentController.addUserScript(
            WKUserScript(
                source: Self.xhrTrackingScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        userContentController.addUserScript(
            WKUserScript(
                source: Self.renderInvalidationScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        userContentController.addUserScript(
            WKUserScript(
                source: Self.consoleTrackingScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
    }

    private func resetScreenshotForNavigation() {
        screenshotNavigationGeneration += 1
        screenshotDirtyVersion += 1
        screenshotCapturedVersion = -1
        screenshotPNG = nil
        screenshotRenderTask?.cancel()
        screenshotRenderTask = nil
    }

    private func markScreenshotDirty(scheduleAfter delay: TimeInterval) {
        guard hasAttemptedNavigation, webView.url != nil else { return }

        screenshotDirtyVersion += 1

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

    private func finishScreenshotWaiters(with result: Result<Data, Error>) {
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

extension BrowserModel: BrowserContextMenuDelegate {}

extension BrowserModel: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else {
            return
        }

        switch message.name {
        case "wkdomainsXHR":
            recordXHRMessage(body)
        case "wkdomainsRender":
            markScreenshotDirty(scheduleAfter: 0.35)
        case "wkdomainsConsole":
            recordConsoleMessage(body)
        default:
            return
        }
    }
}

extension BrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorMessage = nil
        hasAttemptedNavigation = true
        isLoading = true
        estimatedProgress = max(0.08, webView.estimatedProgress)
        resetScreenshotForNavigation()
        resetXHRTracking(for: webView.url)
        syncAddress(from: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        errorMessage = nil
        syncAddress(from: webView)

        if let url = webView.url {
            AppSettingsStore.shared.updateLastVisitedURL(url)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        errorMessage = nil
        estimatedProgress = 1
        syncAddress(from: webView)
        markScreenshotDirty(scheduleAfter: 0.25)
        botTerminal.refreshIfOpen(
            currentURL: webView.url,
            pageTitle: webView.title,
            viewportMode: viewportMode,
            xhrCount: xhrRecords.count
        )

        if let url = webView.url {
            AppSettingsStore.shared.updateLastVisitedURL(url)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if let scheme = url.scheme?.lowercased(), !["http", "https", "about"].contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    private func handleNavigationError(_ error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }

        isLoading = false
        estimatedProgress = 0
        errorMessage = error.localizedDescription
        finishScreenshotWaiters(with: .failure(error))
    }
}

extension BrowserModel: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }

        return nil
    }
}
