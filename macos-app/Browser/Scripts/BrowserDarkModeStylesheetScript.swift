//
//  BrowserDarkModeStylesheetScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeStylesheetScript = [
        BrowserModel.browserDarkModeStylesheetStateScript,
        BrowserModel.browserDarkModeStylesheetVariablesScript,
        BrowserModel.browserDarkModeStylesheetTransformScript,
        BrowserModel.browserDarkModeStylesheetManagersScript,
        BrowserModel.browserDarkModeStylesheetProxyScript
    ].joined(separator: "\n")
}
