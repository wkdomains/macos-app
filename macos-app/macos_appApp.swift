//
//  macos_appApp.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import SwiftUI

@main
struct macos_appApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(browser: appModel.browser)
        }
    }
}
