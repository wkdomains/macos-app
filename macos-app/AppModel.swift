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

        browser = BrowserModel(dataStore: dataStore)
        apiServer = LocalAPIServer(dataStore: dataStore, settings: ServerSettings.load())
        apiServer.start()
    }
}
