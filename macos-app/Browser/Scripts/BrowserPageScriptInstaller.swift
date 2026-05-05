//
//  BrowserPageScriptInstaller.swift
//  macos-app
//

import WebKit

extension BrowserModel {
    func installPageTrackingScripts(on userContentController: WKUserContentController) {
        userContentController.add(self, name: "wkdomainsXHR")
        userContentController.add(self, name: "wkdomainsRender")
        userContentController.add(self, name: "wkdomainsConsole")
        userContentController.add(self, name: "wkdomainsLogin")
        installPageTrackingUserScripts(on: userContentController)
    }

    func reinstallPageTrackingUserScripts() {
        let userContentController = webView.configuration.userContentController
        userContentController.removeAllUserScripts()
        installPageTrackingUserScripts(on: userContentController)
    }

    private func installPageTrackingUserScripts(on userContentController: WKUserContentController) {
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
        if settingsStore.settings.dark {
            userContentController.addUserScript(
                WKUserScript(
                    source: Self.forcedDarkModeScript(disabledSites: settingsStore.darkDisabledSites),
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        }
        userContentController.addUserScript(
            WKUserScript(
                source: Self.jsonViewerScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true,
                in: .defaultClient
            )
        )
        userContentController.addUserScript(
            WKUserScript(
                source: Self.consoleTrackingScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
    }
}
