//
//  BrowserPageScriptInstaller.swift
//  macos-app
//

import Foundation
import WebKit

extension BrowserModel {
    static let darkModeContentWorldName = "wkdomainsDarkMode"

    static var darkModeContentWorld: WKContentWorld {
        WKContentWorld.world(name: darkModeContentWorldName)
    }

    func installPageTrackingScripts(on userContentController: WKUserContentController) {
        BrowserDebugLogging.log("[wkdomains-debug] scripts install handlers")
        userContentController.add(self, name: "wkdomainsXHR")
        userContentController.add(self, name: "wkdomainsRender")
        userContentController.add(self, name: "wkdomainsConsole")
        if Self.darkModeUsesIsolatedContentWorld {
            userContentController.add(self, contentWorld: Self.darkModeContentWorld, name: "wkdomainsConsole")
        }
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
            if Self.darkModeUsesIsolatedContentWorld {
                let pageProxyScript = Self.forcedDarkModePageProxyScript(disabledSites: settingsStore.darkDisabledSites)
                let engineScript = Self.forcedDarkModeScript(disabledSites: settingsStore.darkDisabledSites)
                BrowserDebugLogging.log("[wkdomains-debug] scripts add forcedDarkMode pageProxyLength=\(pageProxyScript.count) engineLength=\(engineScript.count) isolated=true world=\(Self.darkModeContentWorldName)")
                userContentController.addUserScript(
                    WKUserScript(
                        source: pageProxyScript,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true
                    )
                )
                userContentController.addUserScript(
                    WKUserScript(
                        source: engineScript,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true,
                        in: Self.darkModeContentWorld
                    )
                )
            } else {
                let script = Self.forcedDarkModeScript(disabledSites: settingsStore.darkDisabledSites)
                BrowserDebugLogging.log("[wkdomains-debug] scripts add forcedDarkMode length=\(script.count) isolated=false")
                userContentController.addUserScript(
                    WKUserScript(
                        source: script,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true
                    )
                )
            }
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
