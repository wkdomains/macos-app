//
//  ContentView.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import AppKit
import Combine
import SwiftUI
import WebKit

struct XHRRequestRecord: Encodable {
    let id: String
    let kind: String
    let method: String
    let url: String
    let host: String?
    let pageURL: String?
    let pageHost: String?
    let startedAt: Date
    var completedAt: Date?
    var status: Int?
    var responseURL: String?
    var responseBytes: Int?
    var jsonType: String?
    var jsonItems: Int?
    var jsonShape: String?
    var error: String?
}

struct ContentView: View {
    @ObservedObject var browser: BrowserModel
    @FocusState private var isAddressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            browserToolbar
            progressBar

            ZStack {
                BrowserWebView(webView: browser.webView)
                    .opacity(browser.hasAttemptedNavigation ? 1 : 0)

                if !browser.hasAttemptedNavigation {
                    EmptyBrowserState()
                }

                if let errorMessage = browser.errorMessage {
                    BrowserErrorState(message: errorMessage) {
                        browser.reload()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            isAddressFocused = true
        }
    }

    private var browserToolbar: some View {
        HStack(spacing: 8) {
            BrowserToolbarButton(
                systemName: "chevron.left",
                accessibilityLabel: "Back",
                isDisabled: !browser.canGoBack
            ) {
                browser.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)

            BrowserToolbarButton(
                systemName: "chevron.right",
                accessibilityLabel: "Forward",
                isDisabled: !browser.canGoForward
            ) {
                browser.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)

            BrowserToolbarButton(
                systemName: browser.isLoading ? "xmark" : "arrow.clockwise",
                accessibilityLabel: browser.isLoading ? "Stop loading" : "Reload",
                isDisabled: !browser.hasAttemptedNavigation && !browser.isLoading
            ) {
                browser.isLoading ? browser.stopLoading() : browser.reload()
            }
            .keyboardShortcut("r", modifiers: .command)

            HStack(spacing: 8) {
                Image(systemName: browser.isSecurePage ? "lock.fill" : "globe")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(browser.isSecurePage ? .green : .secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                TextField("Enter a website", text: $browser.addressText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .disableAutocorrection(true)
                    .focused($isAddressFocused)
                    .onSubmit {
                        browser.loadCurrentAddress()
                    }
                    .accessibilityLabel("Website address")

                if !browser.addressText.isEmpty {
                    Button {
                        browser.addressText = ""
                        isAddressFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear address")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isAddressFocused ? Color.accentColor.opacity(0.75) : Color(nsColor: .separatorColor).opacity(0.55),
                        lineWidth: isAddressFocused ? 1.5 : 1
                    )
            )

            Button {
                browser.loadCurrentAddress()
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(browser.addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Go")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var progressBar: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.35))
                .frame(height: 1)

            if browser.isLoading {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: max(24, proxy.size.width * browser.estimatedProgress), height: 2)
                        .animation(.easeOut(duration: 0.18), value: browser.estimatedProgress)
                }
                .frame(height: 2)
                .transition(.opacity)
            }
        }
        .frame(height: 2)
    }
}

private struct BrowserToolbarButton: View {
    let systemName: String
    let accessibilityLabel: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? .tertiary : .primary)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isDisabled ? 0.45 : 1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct BrowserWebView: NSViewRepresentable {
    let webView: BrowserWKWebView

    func makeNSView(context: Context) -> BrowserWKWebView {
        webView
    }

    func updateNSView(_ nsView: BrowserWKWebView, context: Context) {}
}

fileprivate protocol BrowserContextMenuDelegate: AnyObject {
    func clearCookiesForCurrentDomain()
}

final class BrowserWKWebView: WKWebView {
    fileprivate weak var browserContextMenuDelegate: BrowserContextMenuDelegate?
    private var contextMenuEventMonitor: Any?

    deinit {
        if let contextMenuEventMonitor {
            NSEvent.removeMonitor(contextMenuEventMonitor)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeContextMenuEventMonitor()
        } else {
            installContextMenuEventMonitor()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        browserContextMenu()
    }

    private func installContextMenuEventMonitor() {
        guard contextMenuEventMonitor == nil else { return }

        contextMenuEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }

            let isContextClick = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))

            guard isContextClick,
                  self.shouldHandleContextMenuEvent(event)
            else {
                return event
            }

            NSMenu.popUpContextMenu(self.browserContextMenu(), with: event, for: self)
            self.window?.invalidateCursorRects(for: self)
            return nil
        }
    }

    private func removeContextMenuEventMonitor() {
        guard let contextMenuEventMonitor else { return }
        NSEvent.removeMonitor(contextMenuEventMonitor)
        self.contextMenuEventMonitor = nil
    }

    private func shouldHandleContextMenuEvent(_ event: NSEvent) -> Bool {
        guard event.window === window,
              isHidden == false,
              alphaValue > 0
        else {
            return false
        }

        let point = convert(event.locationInWindow, from: nil)
        return bounds.contains(point)
    }

    private func browserContextMenu() -> NSMenu {
        let menu = NSMenu()

        let reloadItem = NSMenuItem(
            title: "Reload",
            action: #selector(reloadFromContextMenu),
            keyEquivalent: ""
        )
        reloadItem.target = self
        menu.addItem(reloadItem)

        if url?.host != nil {
            let clearCookiesItem = NSMenuItem(
                title: "Clear cookies",
                action: #selector(clearCookiesFromContextMenu),
                keyEquivalent: ""
            )
            clearCookiesItem.target = self
            menu.addItem(clearCookiesItem)
        }

        return menu
    }

    @objc private func reloadFromContextMenu() {
        reload()
    }

    @objc private func clearCookiesFromContextMenu() {
        browserContextMenuDelegate?.clearCookiesForCurrentDomain()
    }
}

private struct EmptyBrowserState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "globe")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text("Ready to Browse")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Enter a website address above.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct BrowserErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.orange)

            VStack(spacing: 6) {
                Text("Page Couldn’t Load")
                    .font(.system(size: 20, weight: .semibold))

                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 460)
            }

            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.96))
    }
}

final class BrowserModel: NSObject, ObservableObject {
    @Published var addressText = ""
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var estimatedProgress = 0.0
    @Published private(set) var hasAttemptedNavigation = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSecurePage = false

    let webView: BrowserWKWebView

    private var observations: [NSKeyValueObservation] = []
    private var activePageHost: String?
    private var xhrRecords: [XHRRequestRecord] = []
    private var xhrRecordIndexesByID: [String: Int] = [:]

    init(dataStore: WKWebsiteDataStore = .default()) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore

        webView = BrowserWKWebView(frame: .zero, configuration: configuration)

        super.init()

        webView.allowsBackForwardNavigationGestures = true
        webView.browserContextMenuDelegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        installXHRTrackingScript(on: webView.configuration.userContentController)

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

    private func resetXHRTracking(for url: URL?) {
        activePageHost = url?.host?.lowercased()
        xhrRecords.removeAll(keepingCapacity: true)
        xhrRecordIndexesByID.removeAll(keepingCapacity: true)
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

    func load(_ url: URL) {
        hasAttemptedNavigation = true
        errorMessage = nil
        addressText = url.absoluteString
        isSecurePage = url.scheme?.lowercased() == "https"
        resetXHRTracking(for: url)

        webView.load(URLRequest(url: url))
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

    private func installXHRTrackingScript(on userContentController: WKUserContentController) {
        userContentController.add(self, name: "wkdomainsXHR")
        userContentController.addUserScript(
            WKUserScript(
                source: Self.xhrTrackingScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
    }

    private static let xhrTrackingScript = """
    (() => {
      if (window.__wkdomainsXHRInstalled) return;
      window.__wkdomainsXHRInstalled = true;

      let nextID = 1;

      const post = (payload) => {
        try {
          window.webkit.messageHandlers.wkdomainsXHR.postMessage({
            pageURL: location.href,
            pageHost: location.hostname,
            ...payload
          });
        } catch (_) {}
      };

      const requestID = () => `${Date.now()}-${nextID++}`;

      const normalizeURL = (input) => {
        try {
          if (input instanceof Request) return input.url;
          if (input && typeof input === "object" && "href" in input) return input.href;
          return new URL(String(input), location.href).href;
        } catch (_) {
          return String(input);
        }
      };

      const byteSize = (text) => {
        try {
          if (window.TextEncoder) return new TextEncoder().encode(text).length;
        } catch (_) {}

        return String(text || "").length;
      };

      const valueType = (value) => {
        if (value === null) return "null";
        if (Array.isArray(value)) return "array";
        return typeof value;
      };

      const truncatedKeys = (object, limit = 20) => {
        if (!object || typeof object !== "object" || Array.isArray(object)) return [];

        const keys = Object.keys(object);
        if (keys.length <= limit) return keys;

        return keys.slice(0, limit).concat(`+${keys.length - limit} more`);
      };

      const isPlainObject = (value) => {
        return !!value && typeof value === "object" && !Array.isArray(value);
      };

      const hasOnlyKeys = (value, expectedKeys) => {
        if (!isPlainObject(value)) return false;

        const keys = Object.keys(value);
        if (keys.length !== expectedKeys.length) return false;

        return expectedKeys.every((key) => keys.includes(key));
      };

      const isCRUDObject = (value) => {
        return hasOnlyKeys(value, ["c", "r", "u", "d"])
          && ["c", "r", "u", "d"].every((key) => typeof value[key] === "boolean");
      };

      const isCapabilityObject = (value) => {
        return isPlainObject(value) && Object.prototype.hasOwnProperty.call(value, "included");
      };

      const collapsedObjectMap = (object) => {
        const keys = Object.keys(object);
        if (keys.length < 4) return undefined;

        const values = keys.map((key) => object[key]);

        if (values.every(isCRUDObject)) {
          return `object<crud permissions>[${truncatedKeys(object).join(",")}]`;
        }

        if (values.every(isCapabilityObject)) {
          return `object<capabilities>[${truncatedKeys(object).join(",")}]`;
        }

        return undefined;
      };

      const sampleScalar = (value) => {
        const type = valueType(value);

        if (type === "string") {
          const text = value.length > 80 ? `${value.slice(0, 80)}...` : value;
          return JSON.stringify(text);
        }

        if (type === "number" || type === "boolean" || type === "null") {
          return String(value);
        }

        return type;
      };

      const shapeForValue = (value, depth = 0) => {
        const type = valueType(value);

        if (type === "array") {
          const count = value.length;
          if (count === 0) return "array[0]";

          return `array[${count}]<${shapeForValue(value[0], depth + 1)}>`;
        }

        if (type !== "object") return sampleScalar(value);

        const collapsed = collapsedObjectMap(value);
        if (collapsed) return collapsed;

        const keys = truncatedKeys(value, depth === 0 ? 45 : 14);
        if (keys.length === 0) return "object{}";

        if (depth >= 3 || (depth > 0 && Object.keys(value).length > 14)) {
          return `object{${keys.join(",")}}`;
        }

        const fields = keys.map((key) => {
          if (key.startsWith("+") && key.endsWith(" more")) return key;
          return `${key}:${shapeForValue(value[key], depth + 1)}`;
        });

        return `object{${fields.join(",")}}`;
      };

      const summarizeJSON = (text) => {
        const summary = {
          responseBytes: typeof text === "string" ? byteSize(text) : undefined
        };

        if (typeof text !== "string" || text.length === 0) return summary;

        try {
          const jsonText = text.charCodeAt(0) === 0xFEFF ? text.slice(1) : text;
          const value = JSON.parse(jsonText);
          const type = valueType(value);

          summary.jsonType = type;
          summary.jsonShape = shapeForValue(value);

          if (type === "array") {
            summary.jsonItems = value.length;
            return summary;
          }
        } catch (_) {}

        return summary;
      };

      const finishFetch = (id, response, url) => {
        const finishPayload = {
          event: "finish",
          id,
          status: response.status,
          responseURL: response.url || url
        };

        try {
          response.clone().text().then((text) => {
            post({ ...finishPayload, ...summarizeJSON(text) });
          }).catch(() => {
            post(finishPayload);
          });
        } catch (_) {
          post(finishPayload);
        }
      };

      const xhrResponseText = (xhr) => {
        try {
          if (!xhr.responseType || xhr.responseType === "text") return xhr.responseText;
          if (xhr.responseType === "json") return JSON.stringify(xhr.response);
        } catch (_) {}

        try {
          if (xhr.response instanceof ArrayBuffer) return { responseBytes: xhr.response.byteLength };
          if (xhr.response instanceof Blob) return { responseBytes: xhr.response.size };
        } catch (_) {}

        return undefined;
      };

      const originalFetch = window.fetch;
      if (typeof originalFetch === "function") {
        window.fetch = function(input, init) {
          const id = requestID();
          const method = (init && init.method) || (input && input.method) || "GET";
          const url = normalizeURL(input);

          post({ event: "start", id, kind: "fetch", method, url });

          return originalFetch.apply(this, arguments).then((response) => {
            finishFetch(id, response, url);
            return response;
          }).catch((error) => {
            post({
              event: "error",
              id,
              error: error && error.message ? error.message : String(error)
            });
            throw error;
          });
        };
      }

      const OriginalXHR = window.XMLHttpRequest;
      if (typeof OriginalXHR === "function") {
        const originalOpen = OriginalXHR.prototype.open;
        const originalSend = OriginalXHR.prototype.send;

        OriginalXHR.prototype.open = function(method, url) {
          this.__wkdomainsXHR = {
            method: method || "GET",
            url: normalizeURL(url)
          };

          return originalOpen.apply(this, arguments);
        };

        OriginalXHR.prototype.send = function() {
          const info = this.__wkdomainsXHR || {};
          const id = requestID();
          info.id = id;

          post({
            event: "start",
            id,
            kind: "xmlhttprequest",
            method: info.method || "GET",
            url: info.url || ""
          });

          this.addEventListener("loadend", () => {
            const body = xhrResponseText(this);
            const bodySummary = typeof body === "string"
              ? summarizeJSON(body)
              : (body || {});

            post({
              event: "finish",
              id,
              status: this.status,
              responseURL: this.responseURL || info.url || "",
              ...bodySummary
            });
          }, { once: true });

          this.addEventListener("error", () => {
            post({ event: "error", id, error: "XMLHttpRequest error" });
          }, { once: true });

          this.addEventListener("abort", () => {
            post({ event: "error", id, error: "XMLHttpRequest aborted" });
          }, { once: true });

          return originalSend.apply(this, arguments);
        };
      }
    })();
    """
}

extension BrowserModel: BrowserContextMenuDelegate {}

extension BrowserModel: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "wkdomainsXHR",
              let body = message.body as? [String: Any]
        else {
            return
        }

        recordXHRMessage(body)
    }
}

extension BrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorMessage = nil
        hasAttemptedNavigation = true
        isLoading = true
        estimatedProgress = max(0.08, webView.estimatedProgress)
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

#Preview {
    ContentView(browser: BrowserModel())
}
