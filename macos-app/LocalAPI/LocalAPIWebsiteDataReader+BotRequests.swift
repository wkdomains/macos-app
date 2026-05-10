//
//  LocalAPIWebsiteDataReader+BotRequests.swift
//  macos-app
//

import Foundation
@preconcurrency import WebKit

extension WebsiteDataReader {
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
}
