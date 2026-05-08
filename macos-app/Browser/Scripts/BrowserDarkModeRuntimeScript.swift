//
//  BrowserDarkModeRuntimeScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeRuntimeScript = [
        BrowserModel.browserDarkModeRuntimeStateScript,
        BrowserModel.browserDarkModeRuntimeEnvironmentScript,
        BrowserModel.browserDarkModeRuntimeWatchersScript,
        BrowserModel.browserDarkModeRuntimeDynamicScript,
        BrowserModel.browserDarkModeRuntimeLifecycleScript
    ].joined(separator: "\n")
}
