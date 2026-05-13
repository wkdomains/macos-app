//
//  AppModel.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import Combine

@MainActor
final class AppModel: ObservableObject {
    let browser: BrowserModel

    private let apiServer: LocalAPIServer

    init(screenRecorder: ScreenRecorder) {
        let settingsStore = AppSettingsStore.shared
        let apiPort = AppSettingsStore.runtimePortOverride() ?? settingsStore.settings.port
        BrowserDebugLogging.startMainThreadStallMonitor()

        browser = BrowserModel(settingsStore: settingsStore)
        browser.setLocalAPIBaseURL("http://localhost:\(apiPort)")
        apiServer = LocalAPIServer(browser: browser, port: apiPort, screenRecorder: screenRecorder)
        apiServer.portDidChange = { [weak browser] port in
            browser?.setLocalAPIBaseURL("http://localhost:\(port)")
        }
        apiServer.start()
        browser.restoreOpenTabs(settingsStore.startupURLs)
    }
}
