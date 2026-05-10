//
//  LocalAPIWebsiteDataReader.swift
//  macos-app
//

import Foundation
@preconcurrency import WebKit

@MainActor
final class WebsiteDataReader {
    let browser: BrowserModel
    var viewportCaptureSessions: [String: WebKitViewportCaptureSession] = [:]

    init(browser: BrowserModel) {
        self.browser = browser
    }
}
