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

    init(dataStore: WKWebsiteDataStore = .default()) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore

        webView = BrowserWKWebView(frame: .zero, configuration: configuration)

        super.init()

        webView.allowsBackForwardNavigationGestures = true
        webView.browserContextMenuDelegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self

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
}

extension BrowserModel: BrowserContextMenuDelegate {}

extension BrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorMessage = nil
        hasAttemptedNavigation = true
        isLoading = true
        estimatedProgress = max(0.08, webView.estimatedProgress)
        syncAddress(from: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        errorMessage = nil
        syncAddress(from: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        errorMessage = nil
        estimatedProgress = 1
        syncAddress(from: webView)
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
