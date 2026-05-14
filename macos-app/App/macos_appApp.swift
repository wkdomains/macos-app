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
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appModel: AppModel
    @StateObject private var historyFaviconStore = HistoryFaviconStore()
    @StateObject private var bookmarkFaviconStore = HistoryFaviconStore()
    @StateObject private var screenRecorder: ScreenRecorder

    init() {
        let screenRecorder = ScreenRecorder()
        _screenRecorder = StateObject(wrappedValue: screenRecorder)
        _appModel = StateObject(wrappedValue: AppModel(screenRecorder: screenRecorder))
    }

    var body: some Scene {
        Window("", id: "main") {
            ContentView(browser: appModel.browser)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            BrowserTabCommands(browser: appModel.browser)
            ScreenRecordingCommands(recorder: screenRecorder)
            BrowserHistoryCommands(browser: appModel.browser, faviconStore: historyFaviconStore)
            BrowserBookmarksCommands(browser: appModel.browser, faviconStore: bookmarkFaviconStore)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            appModel.browser.saveAllProfileCookiesNow()
        }
    }
}

private struct ScreenRecordingCommands: Commands {
    @ObservedObject var recorder: ScreenRecorder

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(recorder.isRecording ? "Stop Recording" : "Record Entire Screen") {
                recorder.toggleRecording()
            }
            .keyboardShortcut("5", modifiers: [.command, .shift])

            Button(recorder.isPaused ? "Resume Recording" : "Pause Recording") {
                recorder.togglePause()
            }
            .disabled(!recorder.isRecording)
        }
    }
}

private struct BrowserTabCommands: Commands {
    @ObservedObject var browser: BrowserModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") {
                browser.addEmptyTab()
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Close Tab") {
                browser.closeActiveTab()
            }
            .keyboardShortcut("w", modifiers: .command)
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

    fileprivate static func menuTitle(for rawURL: String) -> String {
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

private struct BrowserBookmarksCommands: Commands {
    @ObservedObject var browser: BrowserModel
    @ObservedObject var faviconStore: HistoryFaviconStore

    var body: some Commands {
        CommandMenu("Bookmarks") {
            if browser.bookmarkURLs.isEmpty {
                Button("No Bookmarks") {}
                    .disabled(true)
            } else {
                ForEach(browser.bookmarkURLs, id: \.absoluteString) { url in
                    Button {
                        browser.load(url)
                    } label: {
                        HistoryMenuItemLabel(
                            title: BrowserHistoryCommands.menuTitle(for: url.absoluteString),
                            favicon: faviconStore.image(for: url.absoluteString)
                        )
                    }
                    .help(url.absoluteString)
                }
            }
        }
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
    private var isWaitingForCookieFlush = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillResignActive(_ notification: Notification) {
        BrowserCookiePersistence.saveAllProfileCookies()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isWaitingForCookieFlush else {
            return .terminateLater
        }

        isWaitingForCookieFlush = true
        let finishTermination = { [weak self, weak sender] in
            guard let self,
                  self.isWaitingForCookieFlush
            else {
                return
            }

            self.isWaitingForCookieFlush = false
            sender?.reply(toApplicationShouldTerminate: true)
        }

        BrowserCookiePersistence.saveAllProfileCookies(completion: finishTermination)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: finishTermination)

        return .terminateLater
    }
}
