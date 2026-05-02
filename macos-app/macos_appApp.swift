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
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            self.renameApplicationMenu()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func renameApplicationMenu() {
        guard let appMenuItem = NSApplication.shared.mainMenu?.items.first else { return }

        appMenuItem.title = "wkdomains"

        guard let appMenu = appMenuItem.submenu else { return }

        for item in appMenu.items {
            if item.title.hasPrefix("About ") {
                item.title = "About wkdomains"
            } else if item.title.hasPrefix("Hide ") {
                item.title = "Hide wkdomains"
            } else if item.title.hasPrefix("Quit ") {
                item.title = "Quit wkdomains"
            }
        }
    }
}
