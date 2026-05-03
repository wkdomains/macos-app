//
//  BotTerminalModel.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import Combine
import Foundation

struct BotTerminalRequest: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let currentURL: String
    let pageHost: String
    let domain: String
    let llmsURL: String
    let userAgent: String
    let prompt: String
    var status: String
}

@MainActor
final class BotTerminalModel: ObservableObject {
    nonisolated static let llmsUserAgent = "wkdomains.com bot v0.0.1 - support@wkdomains.com"

    @Published private(set) var message = "Open the agent terminal to start domain discovery."
    @Published private(set) var isOpen = false
    @Published private(set) var isInputReady = false

    private var requests: [BotTerminalRequest] = []
    private var discoveryTask: Task<Void, Never>?
    private var terminalLines: [String] = []
    private var loadingLineIndex: Int?
    private var currentPageContext: PageContext?

    func open(currentURL: URL?, pageTitle: String?, viewportMode: BrowserViewportMode, xhrCount: Int) {
        isOpen = true
        startDiscovery(
            currentURL: currentURL,
            pageTitle: pageTitle,
            viewportMode: viewportMode,
            xhrCount: xhrCount
        )
    }

    func close() {
        isOpen = false
        discoveryTask?.cancel()
        discoveryTask = nil
    }

    func refreshIfOpen(currentURL: URL?, pageTitle: String?, viewportMode: BrowserViewportMode, xhrCount: Int) {
        guard isOpen else { return }

        startDiscovery(
            currentURL: currentURL,
            pageTitle: pageTitle,
            viewportMode: viewportMode,
            xhrCount: xhrCount
        )
    }

    private func startDiscovery(currentURL: URL?, pageTitle: String?, viewportMode: BrowserViewportMode, xhrCount: Int) {
        discoveryTask?.cancel()
        terminalLines = []
        loadingLineIndex = nil
        isInputReady = false
        currentPageContext = nil

        guard let currentURL,
              let host = currentURL.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              !host.isEmpty
        else {
            appendLine("[agent] Open a page first, then open the agent terminal.")
            return
        }

        let domain = DomainUtilities.registrableDomain(from: host)
        let llmsURL = "https://\(domain)/llms.txt"
        currentPageContext = PageContext(
            currentURL: currentURL.absoluteString,
            pageHost: host,
            domain: domain,
            llmsURL: llmsURL,
            pageTitle: pageTitle,
            viewportMode: viewportMode.rawValue,
            xhrCount: xhrCount
        )
        appendLine("wkdomains agent view")
        appendLine("Domain: \(domain)")
        appendLine("Page: \(currentURL.absoluteString)")
        if let pageTitle, !pageTitle.isEmpty {
            appendLine("Title: \(pageTitle)")
        }
        appendLine("Viewport: \(viewportMode.rawValue)")
        appendLine("XHR: \(xhrCount) requests observed")
        appendLine("")
        appendLoadingLine("Loading llms.txt...")

        let request = BotTerminalRequest(
            id: UUID(),
            createdAt: Date(),
            currentURL: currentURL.absoluteString,
            pageHost: host,
            domain: domain,
            llmsURL: llmsURL,
            userAgent: Self.llmsUserAgent,
            prompt: """
            The human opened the wkdomains agent terminal for \(currentURL.absoluteString).

            Use the current page context plus wkdomains local endpoints if available:
            /api/v1/page, /api/v1/dom, /api/v1/links, /api/v1/console, /api/v1/resources, /api/v1/screenshot, /api/v1/xhr/{host}, and /api/v1/cookies/{host}.

            Fetch \(llmsURL) with user-agent '\(Self.llmsUserAgent)' if useful. Explain what this domain offers to an agent, what machine-readable resources exist, and what actions or APIs seem possible. Reply with a concise terminal-ready summary.
            """,
            status: "pending"
        )

        requests.removeAll { $0.status == "pending" }
        requests.append(request)

        discoveryTask = Task { [weak self] in
            guard let self else { return }
            await self.discoverDomain(domain)
        }
    }

    func pendingRequests() -> [BotTerminalRequest] {
        requests.filter { $0.status == "pending" }
    }

    func completeRequest(id: UUID, summary: String) -> Bool {
        guard let index = requests.firstIndex(where: { $0.id == id }) else {
            return false
        }

        requests[index].status = "completed"
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSummary.isEmpty {
            appendLine("[agent] No summary was provided.")
        } else {
            appendLine("")
            appendLine("Agent reply:")
            appendLine(Self.wordLimited(trimmedSummary, limit: 80))
        }

        return true
    }

    func submitHumanMessage(_ rawMessage: String) {
        let humanMessage = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !humanMessage.isEmpty else { return }

        guard let context = currentPageContext else {
            appendLine("")
            appendLine("Human:")
            appendLine(humanMessage)
            appendLine("Agent request could not be queued because no page context is loaded.")
            return
        }

        appendLine("")
        appendLine("Human:")
        appendLine(humanMessage)
        appendLine("Agent: request queued.")

        let request = BotTerminalRequest(
            id: UUID(),
            createdAt: Date(),
            currentURL: context.currentURL,
            pageHost: context.pageHost,
            domain: context.domain,
            llmsURL: context.llmsURL,
            userAgent: Self.llmsUserAgent,
            prompt: """
            The human asked from the wkdomains agent terminal:

            \(humanMessage)

            Current page context:
            URL: \(context.currentURL)
            Title: \(context.pageTitle ?? "")
            Host: \(context.pageHost)
            Domain: \(context.domain)
            Viewport: \(context.viewportMode)
            Observed XHR count: \(context.xhrCount)

            Use wkdomains local endpoints if available:
            /api/v1/page, /api/v1/dom, /api/v1/links, /api/v1/console, /api/v1/resources, /api/v1/screenshot, /api/v1/xhr/{host}, and /api/v1/cookies/{host}.

            Reply concisely for the terminal.
            """,
            status: "pending"
        )

        requests.removeAll { $0.status == "pending" }
        requests.append(request)
    }

    private func discoverDomain(_ domain: String) async {
        var foundLabels: [String] = []
        var apiLine: String?
        var affordances: Set<String> = []

        for path in Self.resourcePaths {
            guard !Task.isCancelled else { return }

            updateLoadingLine("Loading \(Self.displayName(for: path))...")
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }

            let result = await Self.fetchResource(domain: domain, path: path)
            guard !Task.isCancelled else { return }

            if result.found {
                let label = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                foundLabels.append(label)

                if path.contains("openapi") || path.contains("swagger") {
                    apiLine = "API: \(path)"
                    affordances.insert("OpenAPI actions")
                }

                if path.contains("llms") {
                    affordances.insert("llms.txt guidance")
                }

                if path.contains("agent-card") || path.contains("ai-plugin") {
                    affordances.insert("agent metadata")
                }

                if path.contains("sitemap") {
                    affordances.insert("sitemap discovery")
                }

                for affordance in Self.affordances(in: result.bodyPreview) {
                    affordances.insert(affordance)
                }

                if apiLine == nil, let apiHost = Self.apiHost(in: result.bodyPreview) {
                    apiLine = "API: \(apiHost)"
                }
            }
        }

        guard !Task.isCancelled else { return }

        updateLoadingLine("Discovery complete.")
        appendLine("")
        appendLine("Summary:")
        appendLine(Self.discoverySummary(domain: domain, foundLabels: foundLabels, apiLine: apiLine, affordances: affordances))
        isInputReady = true
    }

    private func appendLine(_ line: String) {
        terminalLines.append(line)
        renderMessage()
    }

    private func appendLoadingLine(_ line: String) {
        terminalLines.append(line)
        loadingLineIndex = terminalLines.indices.last
        renderMessage()
    }

    private func updateLoadingLine(_ line: String) {
        guard let loadingLineIndex, terminalLines.indices.contains(loadingLineIndex) else {
            appendLoadingLine(line)
            return
        }

        terminalLines[loadingLineIndex] = line
        renderMessage()
    }

    private func renderMessage() {
        message = terminalLines.joined(separator: "\n")
    }

    private static let resourcePaths = [
        "/llms.txt",
        "/llms-full.txt",
        "/openapi.json",
        "/swagger.json",
        "/.well-known/openapi.json",
        "/.well-known/ai-plugin.json",
        "/.well-known/agent-card.json",
        "/sitemap.xml",
        "/robots.txt"
    ]

    nonisolated private static func fetchResource(domain: String, path: String) async -> ResourceDiscoveryResult {
        guard let url = URL(string: "https://\(domain)\(path)") else {
            return ResourceDiscoveryResult(path: path, status: nil, found: false, bodyPreview: nil, error: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue(llmsUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=0-8191", forHTTPHeaderField: "Range")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let contentType = httpResponse?.value(forHTTPHeaderField: "Content-Type")?.lowercased()
            let isText = contentType?.contains("text") == true
                || contentType?.contains("json") == true
                || contentType?.contains("xml") == true
                || contentType?.contains("markdown") == true
            let preview = isText ? String(data: data, encoding: .utf8).map { String($0.prefix(1600)) } : nil

            return ResourceDiscoveryResult(
                path: path,
                status: httpResponse?.statusCode,
                found: (200..<400).contains(httpResponse?.statusCode ?? 0),
                bodyPreview: preview,
                error: nil
            )
        } catch {
            return ResourceDiscoveryResult(
                path: path,
                status: nil,
                found: false,
                bodyPreview: nil,
                error: error.localizedDescription
            )
        }
    }

    nonisolated private static func apiHost(in preview: String?) -> String? {
        guard let preview else { return nil }

        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\"'<>[]{}(),"))
        let tokens = preview.components(separatedBy: separators)

        for token in tokens {
            guard token.contains("api") else { continue }

            if let url = URL(string: token), let host = url.host, host.contains("api") {
                return host
            }

            let trimmed = token
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/:;"))
            if trimmed.contains(".") && trimmed.contains("api") {
                return trimmed
            }
        }

        return nil
    }

    nonisolated private static func affordances(in preview: String?) -> [String] {
        guard let preview else { return [] }

        let lowercasePreview = preview.lowercased()
        var values: [String] = []

        if lowercasePreview.contains("mcp") {
            values.append("MCP")
        }
        if lowercasePreview.contains("knowledge") {
            values.append("knowledge search")
        }
        if lowercasePreview.contains("oauth") {
            values.append("OAuth")
        }
        if lowercasePreview.contains("webhook") {
            values.append("webhooks")
        }
        if lowercasePreview.contains(".md") || lowercasePreview.contains("markdown") {
            values.append("markdown docs routes")
        }

        return values
    }

    nonisolated private static func displayName(for path: String) -> String {
        path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: ".well-known/", with: "")
    }

    nonisolated private static func discoverySummary(domain: String, foundLabels: [String], apiLine: String?, affordances: Set<String>) -> String {
        let foundText: String
        if foundLabels.isEmpty {
            foundText = "no common agent files"
        } else {
            foundText = foundLabels.prefix(6).joined(separator: ", ")
        }

        let apiText = apiLine?.replacingOccurrences(of: "API: ", with: "") ?? "no OpenAPI endpoint"
        let affordanceText: String
        if affordances.isEmpty {
            affordanceText = "browser context, DOM, XHR, cookies, console, and screenshot inspection"
        } else {
            affordanceText = affordances.sorted().prefix(5).joined(separator: ", ")
        }

        return wordLimited(
            "\(domain) exposes useful agent-facing context. wkdomains found \(foundText), with \(apiText) as the best API signal. The strongest affordances are \(affordanceText). A coding agent can combine these files with the current screenshot, DOM, XHR, cookies, and console state to understand what the page offers and what actions may be possible.",
            limit: 80
        )
    }

    nonisolated private static func wordLimited(_ text: String, limit: Int) -> String {
        let words = text
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard words.count > limit else {
            return words.joined(separator: " ")
        }

        return words.prefix(limit).joined(separator: " ") + "..."
    }

}

private struct PageContext {
    let currentURL: String
    let pageHost: String
    let domain: String
    let llmsURL: String
    let pageTitle: String?
    let viewportMode: String
    let xhrCount: Int
}

private struct ResourceDiscoveryResult {
    let path: String
    let status: Int?
    let found: Bool
    let bodyPreview: String?
    let error: String?

    var statusDescription: String {
        if let status {
            return "\(status)"
        }

        return "unknown"
    }
}
