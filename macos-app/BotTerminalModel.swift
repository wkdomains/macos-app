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
    static let llmsUserAgent = "wkdomains.com bot v0.0.1 - support@wkdomains.com"

    @Published private(set) var message = "Fetching llms.txt..."

    private var requests: [BotTerminalRequest] = []

    func startLLMsRequest(currentURL: URL?) {
        message = "Fetching llms.txt..."

        guard let currentURL,
              let host = currentURL.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              !host.isEmpty
        else {
            message = "Open a page first, then ask the agent to fetch llms.txt."
            return
        }

        let domain = DomainUtilities.registrableDomain(from: host)
        let llmsURL = "https://\(domain)/llms.txt"
        let request = BotTerminalRequest(
            id: UUID(),
            createdAt: Date(),
            currentURL: currentURL.absoluteString,
            pageHost: host,
            domain: domain,
            llmsURL: llmsURL,
            userAgent: Self.llmsUserAgent,
            prompt: "Fetch \(llmsURL) with user-agent '\(Self.llmsUserAgent)' and summarize the file to around 200 words. Reply with the summary for the terminal.",
            status: "pending"
        )

        requests.removeAll { $0.status == "pending" }
        requests.append(request)
    }

    func pendingRequests() -> [BotTerminalRequest] {
        requests.filter { $0.status == "pending" }
    }

    func completeRequest(id: UUID, summary: String) -> Bool {
        guard let index = requests.firstIndex(where: { $0.id == id }) else {
            return false
        }

        requests[index].status = "completed"
        message = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            message = "No summary was provided."
        }

        return true
    }

}
