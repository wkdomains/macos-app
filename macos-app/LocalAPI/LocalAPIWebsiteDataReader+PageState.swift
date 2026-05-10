//
//  LocalAPIWebsiteDataReader+PageState.swift
//  macos-app
//

import Foundation
@preconcurrency import WebKit

extension WebsiteDataReader {
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

    func readScrollTrace(completion: @escaping (Result<Any, Error>) -> Void) {
        let script = """
        JSON.stringify((() => {
          const trace = window.__wkdomainsScrollTrace || null;
          const position = (() => {
            const scrolling = document.scrollingElement || document.documentElement;
            return {
              x: Math.round(window.scrollX || scrolling.scrollLeft || 0),
              y: Math.round(window.scrollY || scrolling.scrollTop || 0),
              maxX: Math.max(0, Math.round(scrolling.scrollWidth - window.innerWidth)),
              maxY: Math.max(0, Math.round(scrolling.scrollHeight - window.innerHeight)),
              viewportWidth: window.innerWidth,
              viewportHeight: window.innerHeight,
              documentWidth: scrolling.scrollWidth,
              documentHeight: scrolling.scrollHeight
            };
          })();

          if (!trace) {
            return {
              ok: true,
              hasTrace: false,
              url: location.href,
              title: document.title,
              position
            };
          }

          const samples = Array.isArray(trace.samples) ? trace.samples : [];
          const plan = Array.isArray(trace.plan) ? trace.plan : [];
          const dwell = samples
            .filter((sample) => sample.event === "pause-start" || sample.event === "completed")
            .map((sample, index) => {
              const next = samples.find((candidate) => candidate.elapsedMs > sample.elapsedMs && (
                candidate.event === "move-start" || candidate.event === "completed"
              ));
              return {
                index,
                event: sample.event,
                elapsedMs: sample.elapsedMs,
                durationMs: next ? Math.max(0, next.elapsedMs - sample.elapsedMs) : (sample.plannedPauseMs || 0),
                position: sample.position,
                dominant: sample.dominant,
                visible: sample.visible,
                interest: sample.interest || null,
                curiosityPause: sample.curiosityPause === true,
                plannedStop: sample.plannedStop || null
              };
            });

          return {
            ok: true,
            hasTrace: true,
            url: location.href,
            title: document.title,
            position,
            trace: {
              id: trace.id,
              status: trace.status || "unknown",
              style: trace.style || null,
              startedAt: trace.startedAt || null,
              completedAt: trace.completedAt || null,
              completedElapsedMs: trace.completedElapsedMs || null,
              requested: trace.requested || null,
              plan,
              planCount: plan.length,
              sampleCount: samples.length,
              current: trace.current || null,
              samples,
              dwell
            }
          };
        })())
        """
        evaluateJSONScript(script, label: "scroll-trace", completion: completion)
    }

    func recordScrollTrace(arguments: [String: Any], completion: @escaping (Result<Any, Error>) -> Void) {
        let action = (arguments["action"] as? String ?? "start").lowercased()
        let script = """
        JSON.stringify((() => {
          const action = \(Self.jsonLiteral(action));
          const scrolling = document.scrollingElement || document.documentElement;

          const scrollPosition = () => ({
            x: Math.round(window.scrollX || scrolling.scrollLeft || 0),
            y: Math.round(window.scrollY || scrolling.scrollTop || 0),
            maxX: Math.max(0, Math.round(scrolling.scrollWidth - window.innerWidth)),
            maxY: Math.max(0, Math.round(scrolling.scrollHeight - window.innerHeight)),
            viewportWidth: window.innerWidth,
            viewportHeight: window.innerHeight,
            documentWidth: scrolling.scrollWidth,
            documentHeight: scrolling.scrollHeight
          });

          const visibleScrollItems = () => {
            const selectors = [
              "main > section",
              "main > article",
              "section",
              "article",
              "[data-section]",
              "h1",
              "h2",
              "h3"
            ].join(",");
            return Array.from(document.querySelectorAll(selectors))
              .map((node) => {
                if (!node || !node.getBoundingClientRect) return null;
                const rect = node.getBoundingClientRect();
                const style = getComputedStyle(node);
                if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return null;
                const visibleHeight = Math.max(0, Math.min(rect.bottom, window.innerHeight) - Math.max(rect.top, 0));
                if (visibleHeight < 24 || rect.width < Math.min(260, window.innerWidth * 0.24)) return null;
                const text = String(node.innerText || node.textContent || "").replace(/\\s+/g, " ").trim().slice(0, 220);
                return {
                  tag: node.tagName.toLowerCase(),
                  id: node.id || null,
                  text,
                  top: Math.round(rect.top),
                  bottom: Math.round(rect.bottom),
                  height: Math.round(rect.height),
                  visibleHeight: Math.round(visibleHeight),
                  visibleRatio: rect.height > 0 ? Number(Math.min(1, visibleHeight / rect.height).toFixed(3)) : 0
                };
              })
              .filter(Boolean)
              .sort((left, right) => right.visibleHeight - left.visibleHeight)
              .slice(0, 8);
          };

          const recordSample = (trace, event, extra = {}) => {
            const visible = visibleScrollItems();
            const sample = {
              event,
              elapsedMs: Math.round(performance.now() - trace.startedAtPerformance),
              at: new Date().toISOString(),
              position: scrollPosition(),
              dominant: visible[0] || null,
              visible,
              ...extra
            };
            trace.samples.push(sample);
            trace.sampleCount = trace.samples.length;
            trace.current = sample;
            return sample;
          };

          const removeExistingRecorder = () => {
            const recorder = window.__wkdomainsManualScrollRecorder || null;
            if (!recorder) return;
            window.removeEventListener("scroll", recorder.onScroll, { passive: true });
            if (recorder.idleTimer) window.clearTimeout(recorder.idleTimer);
            if (recorder.throttleTimer) window.clearTimeout(recorder.throttleTimer);
            window.__wkdomainsManualScrollRecorder = null;
          };

          if (action === "stop") {
            const recorder = window.__wkdomainsManualScrollRecorder || null;
            const trace = window.__wkdomainsScrollTrace || recorder?.trace || null;
            removeExistingRecorder();
            if (trace && trace.status !== "completed") {
              trace.status = "completed";
              trace.completedAt = new Date().toISOString();
              trace.completedElapsedMs = Math.round(performance.now() - trace.startedAtPerformance);
              recordSample(trace, "completed", { source: "manual-stop" });
            }
            return { ok: true, action, hasTrace: Boolean(trace), trace };
          }

          if (action === "reset") {
            removeExistingRecorder();
            window.__wkdomainsScrollTrace = null;
            return { ok: true, action, hasTrace: false };
          }

          removeExistingRecorder();
          const trace = {
            id: `manual-scroll-${Date.now()}-${Math.random().toString(16).slice(2)}`,
            status: "recording",
            style: "manual",
            source: "human",
            url: location.href,
            title: document.title,
            startedAt: new Date().toISOString(),
            startedAtPerformance: performance.now(),
            requested: {
              action: "record",
              startY: scrollPosition().y
            },
            plan: [],
            samples: [],
            sampleCount: 0,
            current: null
          };
          window.__wkdomainsScrollTrace = trace;
          recordSample(trace, "start", { source: "manual-start" });

          const recorder = {
            trace,
            moving: false,
            idleTimer: null,
            throttleTimer: null,
            lastSampleY: scrollPosition().y,
            lastSampleAt: performance.now(),
            onScroll: () => {
              const now = performance.now();
              const position = scrollPosition();
              const moved = Math.abs(position.y - recorder.lastSampleY);
              if (!recorder.moving) {
                recorder.moving = true;
                recordSample(trace, "move-start", { source: "manual", deltaY: Math.round(position.y - recorder.lastSampleY) });
              }
              if (moved >= 80 && now - recorder.lastSampleAt >= 240) {
                recorder.lastSampleY = position.y;
                recorder.lastSampleAt = now;
                recordSample(trace, "scroll", { source: "manual" });
              }
              if (recorder.idleTimer) window.clearTimeout(recorder.idleTimer);
              recorder.idleTimer = window.setTimeout(() => {
                recorder.moving = false;
                recorder.lastSampleY = scrollPosition().y;
                recorder.lastSampleAt = performance.now();
                recordSample(trace, "pause-start", { source: "manual-idle" });
              }, 650);
            }
          };
          window.__wkdomainsManualScrollRecorder = recorder;
          window.addEventListener("scroll", recorder.onScroll, { passive: true });

          return {
            ok: true,
            action: "start",
            hasTrace: true,
            trace: {
              id: trace.id,
              status: trace.status,
              style: trace.style,
              startedAt: trace.startedAt,
              url: trace.url,
              title: trace.title,
              current: trace.current
            }
          };
        })())
        """
        evaluateJSONScript(script, label: "scroll-record", completion: completion)
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

    static func jsonLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let output = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }

        return output
    }
}
