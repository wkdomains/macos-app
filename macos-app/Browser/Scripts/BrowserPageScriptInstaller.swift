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

    func reinstallPageTrackingUserScripts() {
        let userContentController = webView.configuration.userContentController
        BrowserDebugLogging.log("[wkdomains-debug] scripts reinstall begin dark=\(settingsStore.settings.dark) disabledSites=\(settingsStore.darkDisabledSites.count)")
        userContentController.removeAllUserScripts()
        installPageTrackingUserScripts(on: userContentController)
    }

    private func installPageTrackingUserScripts(on userContentController: WKUserContentController) {
        BrowserDebugLogging.log("[wkdomains-debug] scripts install userScripts dark=\(settingsStore.settings.dark) disabledSites=\(settingsStore.darkDisabledSites.count)")
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
        if settingsStore.settings.dark {
            let script = Self.forcedDarkModeScript(disabledSites: settingsStore.darkDisabledSites)
            BrowserDebugLogging.log("[wkdomains-debug] scripts add forcedDarkMode length=\(script.count)")
            userContentController.addUserScript(
                WKUserScript(
                    source: script,
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
    }
}
