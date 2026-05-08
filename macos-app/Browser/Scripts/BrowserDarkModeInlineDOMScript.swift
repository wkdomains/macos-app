//
//  BrowserDarkModeInlineDOMScript.swift
//  macos-app
//

import Foundation

extension BrowserModel {
    static let browserDarkModeInlineDOMScript = [
        BrowserModel.browserDarkModeInlineStateScript,
        BrowserModel.browserDarkModeInlineSourceScript,
        BrowserModel.browserDarkModeInlineApplyScript,
        BrowserModel.browserDarkModeInlineQueueScript
    ].joined(separator: "\n")
}
