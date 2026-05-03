//
//  macos_appApp.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import Foundation
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
            BrowserHistoryCommands(browser: appModel.browser)
        }
    }
}

private struct BrowserHistoryCommands: Commands {
    @ObservedObject var browser: BrowserModel

    var body: some Commands {
        CommandMenu("History") {
            if browser.historyURLs.isEmpty {
                Button("No History") {}
                    .disabled(true)
            } else {
                ForEach(browser.historyURLs, id: \.self) { rawURL in
                    Button(Self.menuTitle(for: rawURL)) {
                        guard let url = URL(string: rawURL) else { return }
                        browser.load(url)
                    }
                    .help(rawURL)
                }
            }
        }
    }

    private static func menuTitle(for rawURL: String) -> String {
        guard let url = URL(string: rawURL), let host = url.host else {
            return trimmed(rawURL)
        }

        let path = url.path.isEmpty || url.path == "/" ? "" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        let fragment = url.fragment.map { "#\($0)" } ?? ""

        return trimmed("\(host)\(path)\(query)\(fragment)")
    }

    private static func trimmed(_ value: String) -> String {
        guard value.count > 90 else { return value }
        return "\(value.prefix(87))..."
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
