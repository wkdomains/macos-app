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

    init() {
        let settingsStore = AppSettingsStore.shared

        browser = BrowserModel(settingsStore: settingsStore)
        browser.setLocalAPIBaseURL("http://localhost:\(settingsStore.settings.port)")
        apiServer = LocalAPIServer(browser: browser, settings: settingsStore.settings)
        apiServer.start()
        browser.restoreOpenTabs(settingsStore.startupURLs)
    }
}
