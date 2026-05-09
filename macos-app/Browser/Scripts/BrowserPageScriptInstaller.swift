//
//  BrowserPageScriptInstaller.swift
//  macos-app
//

import Foundation
import WebKit

extension BrowserModel {
    func installPageTrackingScripts(on userContentController: WKUserContentController) {
        BrowserDebugLogging.log("[wkdomains-debug] scripts install handlers")
        userContentController.add(self, name: "wkdomainsXHR")
        userContentController.add(self, name: "wkdomainsRender")
        userContentController.add(self, name: "wkdomainsConsole")
        userContentController.add(self, name: "wkdomainsLogin")
        installPageTrackingUserScripts(on: userContentController)
    }

    private func installPageTrackingUserScripts(on userContentController: WKUserContentController) {
        BrowserDebugLogging.log("[wkdomains-debug] scripts install userScripts")
        userContentController.addUserScript(
            WKUserScript(
                source: Self.xhrTrackingScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        userContentController.addUserScript(
            WKUserScript(
                source: Self.renderInvalidationScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        userContentController.addUserScript(
            WKUserScript(
                source: Self.consoleTrackingScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        userContentController.addUserScript(
            WKUserScript(
                source: Self.jsonViewerScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true,
                in: .defaultClient
            )
        )
    }
}
