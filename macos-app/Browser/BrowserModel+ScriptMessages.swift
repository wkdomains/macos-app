//
//  BrowserModel+ScriptMessages.swift
//  macos-app
//

import Foundation
import WebKit

extension BrowserModel: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let startedAt = BrowserDebugLogging.timestamp()
        defer {
            BrowserDebugLogging.logSlowOperation(
                "script-message",
                since: startedAt,
                threshold: 0.02,
                details: "name=\(message.name) bodyType=\(String(describing: type(of: message.body)))"
            )
        }

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
        case "wkdomainsLogin":
            saveCapturedLogin(body)
        default:
            return
        }
    }
}
