//
//  AppModel.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import Combine
import WebKit

@MainActor
final class AppModel: ObservableObject {
    let browser: BrowserModel

    private let apiServer: LocalAPIServer

    init() {
        let dataStore = WKWebsiteDataStore.default()
        let settingsStore = AppSettingsStore.shared

        browser = BrowserModel(dataStore: dataStore)
        browser.setLocalAPIBaseURL("http://localhost:\(settingsStore.settings.port)")
        apiServer = LocalAPIServer(browser: browser, settings: settingsStore.settings)
        apiServer.start()
        browser.load(settingsStore.startupURL)
    }
}
