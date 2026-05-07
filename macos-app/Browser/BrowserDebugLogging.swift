//
//  BrowserDebugLogging.swift
//  macos-app
//

import Foundation

enum BrowserDebugLogging {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "wkdomains.debugLogging")
    }

    static var darkModeScriptEnabled: Bool {
        isEnabled || UserDefaults.standard.bool(forKey: "wkdomains.darkModeDebugLogging")
    }

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        NSLog("%@", message())
    }
}
