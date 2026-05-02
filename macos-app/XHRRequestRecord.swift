//
//  XHRRequestRecord.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import Foundation

struct XHRRequestRecord: Encodable {
    let id: String
    let kind: String
    let method: String
    let url: String
    let host: String?
    let pageURL: String?
    let pageHost: String?
    let startedAt: Date
    var completedAt: Date?
    var status: Int?
    var responseURL: String?
    var responseBytes: Int?
    var jsonType: String?
    var jsonItems: Int?
    var jsonShape: String?
    var error: String?
}
