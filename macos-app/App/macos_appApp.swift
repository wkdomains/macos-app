//
//  macos_appApp.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import Foundation
import AppKit
import Combine
import SwiftUI

@main
struct macos_appApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()
    @StateObject private var historyFaviconStore = HistoryFaviconStore()

    var body: some Scene {
        Window("wkdomains", id: "main") {
            ContentView(browser: appModel.browser)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            BrowserHistoryCommands(browser: appModel.browser, faviconStore: historyFaviconStore)
        }
    }
}

private struct BrowserHistoryCommands: Commands {
    @ObservedObject var browser: BrowserModel
    @ObservedObject var faviconStore: HistoryFaviconStore

    var body: some Commands {
        CommandMenu("History") {
            if browser.historyURLs.isEmpty {
                Button("No History") {}
                    .disabled(true)
            } else {
                ForEach(browser.historyURLs, id: \.self) { rawURL in
                    Button {
                        guard let url = URL(string: rawURL) else { return }
                        browser.load(url)
                    } label: {
                        HistoryMenuItemLabel(
                            title: Self.menuTitle(for: rawURL),
                            favicon: faviconStore.image(for: rawURL)
                        )
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

private struct HistoryMenuItemLabel: View {
    let title: String
    let favicon: NSImage?

    var body: some View {
        if let favicon {
            Label {
                Text(title)
            } icon: {
                Image(nsImage: favicon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
        } else {
            Label(title, systemImage: "globe")
        }
    }
}

@MainActor
private final class HistoryFaviconStore: ObservableObject {
    @Published private var images: [String: NSImage] = [:]
    private var requestedURLs = Set<String>()
    private var failedURLs = Set<String>()

    func image(for rawURL: String) -> NSImage? {
        if images[rawURL] == nil {
            requestImage(for: rawURL)
        }

        return images[rawURL]
    }

    private func requestImage(for rawURL: String) {
        guard !failedURLs.contains(rawURL),
              requestedURLs.insert(rawURL).inserted,
              let faviconURL = Self.faviconURL(for: rawURL)
        else {
            return
        }

        Task {
            let imageData = try? await Self.fetchData(from: faviconURL)

            if let imageData, let image = NSImage(data: imageData) {
                images[rawURL] = image
            } else {
                failedURLs.insert(rawURL)
            }
        }
    }

    private static func fetchData(from url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    private static func faviconURL(for rawURL: String) -> URL? {
        guard let url = URL(string: rawURL),
              var components = URLComponents(string: "https://www.google.com/s2/favicons")
        else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "domain_url", value: url.absoluteString),
            URLQueryItem(name: "sz", value: "32")
        ]

        return components.url
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
