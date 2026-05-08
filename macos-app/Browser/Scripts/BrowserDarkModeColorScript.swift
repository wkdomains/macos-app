//
//  BrowserDarkModeColorScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeColorScript = [
        BrowserModel.browserDarkModeColorBaseScript,
        BrowserModel.browserDarkModeColorParsingScript,
        BrowserModel.browserDarkModeColorThemeScript,
        BrowserModel.browserDarkModeColorTransformScript
    ].joined(separator: "\n")
}
