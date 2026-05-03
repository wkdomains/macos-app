//
//  ConsoleMessageRecord.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import Foundation

struct ConsoleMessageRecord {
    let id: UUID
    let level: String
    let message: String
    let arguments: [String]
    let pageURL: String?
    let pageHost: String?
    let stack: String?
    let createdAt: Date
}
