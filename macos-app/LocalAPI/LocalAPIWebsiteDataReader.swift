//
//  LocalAPIWebsiteDataReader.swift
//  macos-app
//

import Foundation
@preconcurrency import WebKit

@MainActor
final class WebsiteDataReader {
    let browser: BrowserModel
    var viewportCaptureSessions: [String: WebKitViewportCaptureSession] = [:]

    init(browser: BrowserModel) {
        self.browser = browser
    }

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

                    self.waitForCondition(waitFor) { waitResult in
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
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard BrowserModel.waitInspectionScript(arguments: waitFor) != nil else {
            completion(.failure(InspectionError.invalidActionRequest))
            return
        }

        let timeout = waitTimeout(from: waitFor)
        let startedAt = Date()

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
                    if dictionary["ok"] as? Bool == true {
                        dictionary["elapsedMilliseconds"] = Int(Date().timeIntervalSince(startedAt) * 1000)
                        completion(.success(dictionary))
                        return
                    }

                    if Date().timeIntervalSince(startedAt) >= timeout {
                        dictionary["timedOut"] = true
                        dictionary["elapsedMilliseconds"] = Int(Date().timeIntervalSince(startedAt) * 1000)
                        completion(.success(dictionary))
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


    func navigate(
        to rawURL: String,
        mode rawMode: String?,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let url = resolvedNavigationURL(from: rawURL) else {
            completion(.failure(InspectionError.invalidNavigationURL))
            return
        }

        let mode = rawMode?.lowercased() ?? "auto"

        switch mode {
        case "hard":
            hardNavigate(to: url, completion: completion)
        case "soft":
            softNavigate(to: url, fallbackToHard: false, completion: completion)
        case "auto":
            if currentOriginMatches(url) {
                softNavigate(to: url, fallbackToHard: true, completion: completion)
            } else {
                hardNavigate(to: url, completion: completion)
            }
        default:
            completion(.failure(InspectionError.invalidNavigationRequest))
        }
    }

    func readPage() -> PageResponse {
        let url = browser.webView.url
        let host = url?.host?.lowercased()
        let viewportWidth = browser.viewportMode.width ?? browser.webView.bounds.width

        return PageResponse(
            url: url?.absoluteString,
            title: browser.webView.title,
            host: host,
            domain: host.map(DomainUtilities.registrableDomain(from:)),
            origin: url.map(Self.originString(from:)),
            viewportMode: browser.viewportMode.rawValue,
            viewportWidth: Int(viewportWidth.rounded()),
            viewportHeight: Int(browser.webView.bounds.height.rounded()),
            isLoading: browser.webView.isLoading,
            canGoBack: browser.webView.canGoBack,
            canGoForward: browser.webView.canGoForward
        )
    }

    func readConsoleMessages() -> ConsoleMessagesResponse {
        let messages = browser.consoleMessages().map(ConsoleMessageResponse.init(record:))

        return ConsoleMessagesResponse(
            activePageURL: browser.webView.url?.absoluteString,
            activePageHost: browser.webView.url?.host,
            captureScope: "page JavaScript console calls, window errors, unhandled promise rejections, and CSP violations captured inside WKWebView; browser-engine DevTools diagnostics are not exposed by WKWebView",
            capturedLevels: ["debug", "error", "info", "log", "warn"],
            messages: messages
        )
    }

    func readSnapshot(completion: @escaping (Result<Any, Error>) -> Void) {
        evaluateJSONScript(BrowserModel.snapshotInspectionScript, label: "snapshot", completion: completion)
    }

    func readObserve(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard browser.webView.url != nil else {
            completion(.failure(InspectionError.noPageLoaded))
            return
        }

        readSnapshot { [weak self] snapshotResult in
            guard let self else { return }

            switch snapshotResult {
            case .failure(let error):
                completion(.failure(error))
            case .success(let snapshot):
                guard let snapshotDomain = Self.domain(fromSnapshot: snapshot) else {
                    completion(.failure(InspectionError.noPageLoaded))
                    return
                }

                self.readCookieAuthShape(for: snapshotDomain) { auth in
                    self.readResources(for: snapshotDomain.host) { resources in
                        completion(
                            .success(
                                self.observeResponse(
                                    snapshot: snapshot,
                                    domain: snapshotDomain,
                                    resources: resources,
                                    auth: auth
                                )
                            )
                        )
                    }
                }
            }
        }
    }

    func readDOM(completion: @escaping (Result<Any, Error>) -> Void) {
        evaluateJSONScript(BrowserModel.domInspectionScript, label: "dom", completion: completion)
    }

    func readLinks(completion: @escaping (Result<Any, Error>) -> Void) {
        evaluateJSONScript(BrowserModel.linksInspectionScript, label: "links", completion: completion)
    }

    func readResources(completion: @escaping (DomainResourcesResponse) -> Void) {
        guard let host = browser.webView.url?.host?.lowercased() else {
            completion(DomainResourcesResponse(domain: nil, pageHost: nil, resources: []))
            return
        }

        readResources(for: host, completion: completion)
    }

    private func readResources(for host: String, completion: @escaping (DomainResourcesResponse) -> Void) {
        let domain = DomainUtilities.registrableDomain(from: host)
        let candidates = Self.resourceCandidates(for: domain)

        Task {
            var resources: [DomainResourceResponse] = []

            for candidate in candidates {
                resources.append(await Self.fetchResource(candidate))
            }

            completion(
                DomainResourcesResponse(
                    domain: domain,
                    pageHost: host,
                    resources: resources
                )
            )
        }
    }

    func readDarkReaderStatus(completion: @escaping (Result<Any, Error>) -> Void) {
        guard browser.webView.url != nil else {
            completion(.failure(InspectionError.noPageLoaded))
            return
        }

        let script = """
        JSON.stringify((() => {
            const root = document.documentElement;
            const bodyStyle = document.body ? getComputedStyle(document.body) : null;
            const rootStyle = root ? getComputedStyle(root) : null;
            const darkReaderStyles = Array.from(document.querySelectorAll(".darkreader")).map((element) => ({
                tag: element.tagName.toLowerCase(),
                className: element.className || null,
                media: element.media || null,
                textLength: element.textContent ? element.textContent.length : 0
            }));
            const meta = document.querySelector('meta[name="darkreader"]');
            const lock = document.querySelector('meta[name="darkreader-lock"]');

            return {
                extension: __WKDOMAINS_DARK_READER_EXTENSION_STATUS__,
                url: location.href,
                title: document.title,
                readyState: document.readyState,
                darkReader: {
                    mode: root ? root.getAttribute("data-darkreader-mode") : null,
                    scheme: root ? root.getAttribute("data-darkreader-scheme") : null,
                    documentClasses: root ? Array.from(root.classList) : [],
                    styleCount: darkReaderStyles.length,
                    styles: darkReaderStyles,
                    hasMeta: !!meta,
                    hasLock: !!lock,
                    metaContent: meta ? meta.content || null : null,
                    cssVariables: rootStyle ? {
                        neutralBackground: rootStyle.getPropertyValue("--darkreader-neutral-background").trim() || null,
                        neutralText: rootStyle.getPropertyValue("--darkreader-neutral-text").trim() || null,
                        selectionBackground: rootStyle.getPropertyValue("--darkreader-selection-background").trim() || null,
                        selectionText: rootStyle.getPropertyValue("--darkreader-selection-text").trim() || null
                    } : null
                },
                computedColors: {
                    rootBackground: rootStyle ? rootStyle.backgroundColor : null,
                    rootColor: rootStyle ? rootStyle.color : null,
                    bodyBackground: bodyStyle ? bodyStyle.backgroundColor : null,
                    bodyColor: bodyStyle ? bodyStyle.color : null
                },
                colorScheme: rootStyle ? rootStyle.colorScheme : null,
                prefersColorSchemeDark: !!(window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches)
            };
        })())
        """

        guard
            let extensionData = try? JSONSerialization.data(withJSONObject: BrowserWebExtension.shared.status),
            let extensionJSON = String(data: extensionData, encoding: .utf8)
        else {
            completion(.failure(InspectionError.couldNotEncodeDiagnosticJSON))
            return
        }

        evaluateJSONScript(
            script.replacingOccurrences(of: "__WKDOMAINS_DARK_READER_EXTENSION_STATUS__", with: extensionJSON),
            label: "dark-reader",
            completion: completion
        )
    }

    func readPendingBotRequests() -> [[String: Any]] {
        browser.pendingBotRequests().map(Self.dictionary(from:))
    }

    func waitForPendingBotRequests(timeout: TimeInterval, completion: @escaping (_ requests: [[String: Any]], _ timedOut: Bool) -> Void) {
        browser.waitForPendingBotRequests(timeout: timeout) { requests, timedOut in
            completion(requests.map(Self.dictionary(from:)), timedOut)
        }
    }

    func replyToBotRequest(id: UUID, summary: String) -> Bool {
        browser.replyToBotRequest(id: id, summary: summary)
    }

    func updateBotRequest(id: UUID, status: String) -> Bool {
        browser.updateBotRequest(id: id, status: status)
    }

    func readCurrentPage() -> [String: Any] {
        var response: [String: Any] = [:]

        if let url = browser.webView.url {
            response["url"] = url.absoluteString
            response["host"] = url.host
        }

        return response
    }

    func resolvedNavigationURL(from rawURL: String) -> URL? {
        let value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let url: URL?
        if let currentURL = browser.webView.url {
            url = URL(string: value, relativeTo: currentURL)?.absoluteURL
        } else {
            url = URL(string: value)
        }

        if let url,
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           url.host != nil {
            return url
        }

        if let resolution = AddressResolver.resolve(value) {
            return resolution.primaryURL
        }

        return nil
    }

    private func hardNavigate(to url: URL, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        let beforeURL = browser.webView.url?.absoluteString
        browser.load(url)
        let startedAt = Date()
        var didForceLoad = false

        func poll() {
            let elapsed = Date().timeIntervalSince(startedAt)
            let currentURL = self.browser.webView.url?.absoluteString
            let reachedURL = currentURL == url.absoluteString

            if !didForceLoad, currentURL == nil, !self.browser.webView.isLoading, elapsed >= 0.4 {
                didForceLoad = true
                BrowserDebugLogging.log("[wkdomains-debug] local-api navigate hard forcing direct webview load url=\(url.absoluteString)")
                self.browser.webView.load(URLRequest(url: url))
            }

            if reachedURL && (!self.browser.webView.isLoading || elapsed >= 1.0) {
                completion(
                    .success([
                        "ok": true,
                        "mode": "hard",
                        "requestedURL": url.absoluteString,
                        "beforeURL": Self.json(beforeURL),
                        "url": currentURL ?? url.absoluteString,
                        "forcedWebViewLoad": didForceLoad,
                        "elapsedMilliseconds": Int(elapsed * 1000)
                    ])
                )
                return
            }

            if elapsed >= 8 {
                completion(
                    .success([
                        "ok": false,
                        "mode": "hard",
                        "requestedURL": url.absoluteString,
                        "beforeURL": Self.json(beforeURL),
                        "url": Self.json(currentURL),
                        "forcedWebViewLoad": didForceLoad,
                        "timedOut": true,
                        "elapsedMilliseconds": Int(elapsed * 1000)
                    ])
                )
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                poll()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            poll()
        }
    }

    private func softNavigate(
        to url: URL,
        fallbackToHard: Bool,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard browser.webView.url != nil else {
            completion(.failure(InspectionError.noPageLoaded))
            return
        }

        guard currentOriginMatches(url) else {
            if fallbackToHard {
                hardNavigate(to: url, completion: completion)
            } else {
                completion(.failure(InspectionError.softNavigationRequiresSameOrigin))
            }
            return
        }

        guard let urlData = try? JSONEncoder().encode(url.absoluteString),
              let urlJSON = String(data: urlData, encoding: .utf8)
        else {
            completion(.failure(InspectionError.couldNotEncodeDiagnosticJSON))
            return
        }

        let script = """
        JSON.stringify((() => {
            const target = new URL(\(urlJSON), location.href);
            const beforeURL = location.href;
            const beforeHash = location.hash;

            if (target.origin !== location.origin) {
                return {
                    ok: false,
                    mode: "soft",
                    reason: "cross-origin",
                    requestedURL: target.href,
                    beforeURL,
                    url: location.href
                };
            }

            if (target.href !== location.href) {
                history.pushState(history.state, "", target.href);
                window.dispatchEvent(new PopStateEvent("popstate", { state: history.state }));

                if (beforeHash !== target.hash) {
                    window.dispatchEvent(new HashChangeEvent("hashchange", {
                        oldURL: beforeURL,
                        newURL: target.href
                    }));
                }
            }

            return {
                ok: true,
                mode: "soft",
                requestedURL: target.href,
                beforeURL,
                url: location.href,
                changed: beforeURL !== location.href
            };
        })())
        """

        evaluateJSONScript(script, label: "navigate-soft") { [weak self] result in
            switch result {
            case .success(let response):
                if let dictionary = response as? [String: Any],
                   dictionary["ok"] as? Bool == true {
                    completion(.success(dictionary))
                } else if fallbackToHard {
                    self?.hardNavigate(to: url, completion: completion)
                } else {
                    completion(.failure(InspectionError.softNavigationRequiresSameOrigin))
                }
            case .failure(let error):
                if fallbackToHard {
                    self?.hardNavigate(to: url, completion: completion)
                } else {
                    completion(.failure(error))
                }
            }
        }
    }

    private func currentOriginMatches(_ url: URL) -> Bool {
        guard let currentURL = browser.webView.url else { return false }
        return Self.originString(from: currentURL) == Self.originString(from: url)
    }

    private func observeResponse(
        snapshot: Any,
        domain: RequestedDomain,
        resources: DomainResourcesResponse,
        auth: [String: Any]
    ) -> [String: Any] {
        let console = readConsoleMessages()
        let xhr = readXHRRequests(for: domain)

        return [
            "generatedAt": Self.iso8601Formatter.string(from: Date()),
            "page": pageDictionary(fromSnapshot: snapshot),
            "screenshot": [
                "available": browser.webView.url != nil,
                "endpoint": "/api/v1/screenshot",
                "contentType": "image/png",
                "scope": "current visible viewport"
            ],
            "snapshot": snapshot,
            "console": consoleDictionary(from: console),
            "xhr": xhrDictionary(from: xhr),
            "resources": resourcesDictionary(from: resources),
            "auth": auth
        ]
    }

    func currentPageDomain() throws -> RequestedDomain {
        guard let url = browser.webView.url,
              let domain = RequestedDomain(url: url)
        else {
            throw InspectionError.noPageLoaded
        }

        return domain
    }

    private func pageDictionary(fromSnapshot snapshot: Any) -> [String: Any] {
        let snapshotDictionary = snapshot as? [String: Any]
        let urlString = snapshotDictionary?["url"] as? String
        let url = urlString.flatMap(URL.init(string:))
        let host = url?.host?.lowercased()
        let viewport = snapshotDictionary?["viewport"] as? [String: Any]

        return [
            "url": Self.json(urlString),
            "title": Self.json(snapshotDictionary?["title"] as? String),
            "host": Self.json(host),
            "domain": Self.json(host.map(DomainUtilities.registrableDomain(from:))),
            "origin": Self.json(url.map(Self.originString(from:))),
            "viewportMode": browser.viewportMode.rawValue,
            "viewportWidth": viewport?["width"] as? Int ?? Int(browser.webView.bounds.width.rounded()),
            "viewportHeight": viewport?["height"] as? Int ?? Int(browser.webView.bounds.height.rounded()),
            "isLoading": browser.webView.isLoading,
            "canGoBack": browser.webView.canGoBack,
            "canGoForward": browser.webView.canGoForward
        ]
    }

    private func consoleDictionary(from console: ConsoleMessagesResponse) -> [String: Any] {
        [
            "activePageURL": Self.json(console.activePageURL),
            "activePageHost": Self.json(console.activePageHost),
            "captureScope": console.captureScope,
            "capturedLevels": console.capturedLevels,
            "messages": console.messages.suffix(50).map { message in
                [
                    "id": message.id.uuidString,
                    "level": message.level,
                    "message": message.message,
                    "arguments": message.arguments,
                    "pageURL": Self.json(message.pageURL),
                    "pageHost": Self.json(message.pageHost),
                    "stack": Self.json(message.stack),
                    "createdAt": Self.iso8601Formatter.string(from: message.createdAt)
                ] as [String: Any]
            }
        ]
    }

    private func xhrDictionary(from xhr: XHRRequestsResponse) -> [String: Any] {
        [
            "hostname": xhr.hostname,
            "activePageURL": Self.json(xhr.activePageURL),
            "activePageHost": Self.json(xhr.activePageHost),
            "requests": xhr.requests.prefix(80).map { request in
                [
                    "id": request.id,
                    "kind": request.kind,
                    "method": request.method,
                    "url": request.url,
                    "host": Self.json(request.host),
                    "pageURL": Self.json(request.pageURL),
                    "pageHost": Self.json(request.pageHost),
                    "startedAt": Self.iso8601Formatter.string(from: request.startedAt),
                    "completedAt": Self.json(request.completedAt.map(Self.iso8601Formatter.string(from:))),
                    "status": Self.json(request.status),
                    "responseURL": Self.json(request.responseURL),
                    "responseBytes": Self.json(request.responseBytes),
                    "jsonType": Self.json(request.jsonType),
                    "jsonItems": Self.json(request.jsonItems),
                    "jsonShape": Self.json(request.jsonShape),
                    "responseBodyPreview": Self.json(request.responseBodyPreview),
                    "error": Self.json(request.error)
                ] as [String: Any]
            }
        ]
    }

    private func resourcesDictionary(from resources: DomainResourcesResponse) -> [String: Any] {
        [
            "domain": Self.json(resources.domain),
            "pageHost": Self.json(resources.pageHost),
            "resources": resources.resources.map { resource in
                [
                    "url": resource.url,
                    "path": resource.path,
                    "status": Self.json(resource.status),
                    "found": resource.found,
                    "contentType": Self.json(resource.contentType),
                    "contentLength": Self.json(resource.contentLength),
                    "sampledBytes": resource.sampledBytes,
                    "bodyPreview": Self.json(resource.bodyPreview),
                    "error": Self.json(resource.error)
                ] as [String: Any]
            }
        ]
    }

    private static func domain(fromSnapshot snapshot: Any) -> RequestedDomain? {
        guard let dictionary = snapshot as? [String: Any],
              let urlString = dictionary["url"] as? String,
              let url = URL(string: urlString)
        else {
            return nil
        }

        return RequestedDomain(url: url)
    }

    static func json(_ value: String?) -> Any {
        if let value {
            return value
        }

        return NSNull()
    }

    static func json(_ value: Int?) -> Any {
        if let value {
            return value
        }

        return NSNull()
    }

    private func evaluateJSONScript(_ script: String, label: String, completion: @escaping (Result<Any, Error>) -> Void) {
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

    private static func dictionary(from request: BotTerminalRequest) -> [String: Any] {
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

    private static func resourceCandidates(for domain: String) -> [URL] {
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

    private static func fetchResource(_ url: URL) async -> DomainResourceResponse {
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
