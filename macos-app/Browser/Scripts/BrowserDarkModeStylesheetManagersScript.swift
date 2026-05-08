//
//  BrowserDarkModeStylesheetManagersScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStylesheetManagersScript = [
        BrowserModel.browserDarkModeStylesheetManagerCoreScript,
        BrowserModel.browserDarkModeAdoptedStylesheetManagersScript,
        BrowserModel.browserDarkModeStylesheetVariableUpdatesScript,
        BrowserModel.browserDarkModeStylesheetSyncScript
    ].joined(separator: "\n")
}
