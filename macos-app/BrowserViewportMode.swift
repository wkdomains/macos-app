//
//  BrowserViewportMode.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import CoreGraphics

enum BrowserViewportMode: String, CaseIterable, Identifiable {
    case desktop
    case mobileLarge
    case mobileSmall

    var id: Self { self }

    var width: CGFloat? {
        switch self {
        case .desktop:
            return nil
        case .mobileLarge:
            return 700
        case .mobileSmall:
            return 390
        }
    }

    var systemName: String {
        switch self {
        case .desktop:
            return "desktopcomputer"
        case .mobileLarge:
            return "ipad"
        case .mobileSmall:
            return "iphone"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .desktop:
            return "Desktop viewport"
        case .mobileLarge:
            return "Mobile large viewport"
        case .mobileSmall:
            return "Mobile small viewport"
        }
    }

    var helpText: String {
        switch self {
        case .desktop:
            return "Desktop viewport"
        case .mobileLarge:
            return "Mobile Large: 700px"
        case .mobileSmall:
            return "Mobile Small: 390px"
        }
    }
}
