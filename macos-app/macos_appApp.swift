//
//  macos_appApp.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import SwiftUI

@main
struct macos_appApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        Window("wkdomains", id: "main") {
            ContentView(browser: appModel.browser)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
