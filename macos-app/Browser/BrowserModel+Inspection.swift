//
//  BrowserModel+Inspection.swift
//  macos-app
//

import AppKit
import Foundation
import WebKit

extension BrowserModel {
    func xhrRequests(for host: String) -> [XHRRequestRecord] {
        let normalizedHost = Self.normalizedHost(host)

        return xhrRecords.filter { record in
            guard let recordHost = record.host ?? URL(string: record.url)?.host else {
                return false
            }

            return Self.host(recordHost, matches: normalizedHost)
        }
    }

    func sortedXHRRequests(for host: String) -> [XHRRequestRecord] {
        xhrRequests(for: host).sorted { left, right in
            let leftBytes = Self.xhrResponseByteSortKey(left)
            let rightBytes = Self.xhrResponseByteSortKey(right)

            if leftBytes == rightBytes {
                return left.startedAt < right.startedAt
            }

            return leftBytes > rightBytes
        }
    }

    var xhrContextMenuItems: [XHRContextMenuItem] {
        guard let host = webView.url?.host else {
            return []
        }

        return sortedXHRRequests(for: host)
            .prefix(9)
            .enumerated()
            .map { offset, record in
                XHRContextMenuItem(index: offset, title: Self.xhrMenuTitle(for: record, at: offset))
            }
    }

    func openXHRFromContextMenu(at index: Int) {
        guard let host = webView.url?.host else {
            showAlert(message: "No Page Loaded", detail: InspectionError.noPageLoaded.localizedDescription)
            return
        }

        let requests = sortedXHRRequests(for: host)
        guard requests.indices.contains(index) else {
            showAlert(message: "XHR Not Available", detail: InspectionError.xhrIndexOutOfRange(index).localizedDescription)
            return
        }

        let record = requests[index]
        guard let url = URL(string: record.url) else {
            showAlert(message: "XHR Not Available", detail: InspectionError.invalidXHRURL.localizedDescription)
            return
        }

        let xhr = XHRRequestResponse(record: record)
        let dataStore = webView.configuration.websiteDataStore
        dataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let cookieHeader = WebsiteDataReader.cookieHeader(for: url, from: cookies)

                do {
                    let response = try await WebsiteDataReader.fetchXHRJSON(
                        xhr: xhr,
                        url: url,
                        cookieHeader: cookieHeader
                    )
                    self.displayXHRJSON(response, from: url)
                } catch {
                    self.showAlert(message: "Could Not Open XHR", detail: error.localizedDescription)
                }
            }
        }
    }

    func consoleMessages() -> [ConsoleMessageRecord] {
        consoleRecords
    }

    func recordConsoleMessage(_ message: [String: Any]) {
        let rawArguments = message["arguments"] as? [Any] ?? []
        let arguments = rawArguments.map { value in
            if let value = value as? String {
                return value
            }

            return String(describing: value)
        }

        let record = ConsoleMessageRecord(
            id: UUID(),
            level: message["level"] as? String ?? "log",
            message: message["message"] as? String ?? arguments.joined(separator: " "),
            arguments: arguments,
            pageURL: message["pageURL"] as? String,
            pageHost: (message["pageHost"] as? String)?.lowercased(),
            stack: message["stack"] as? String,
            createdAt: Date()
        )

        consoleRecords.append(record)
        if consoleRecords.count > 200 {
            consoleRecords.removeFirst(consoleRecords.count - 200)
        }
    }

    func recordXHRMessage(_ message: [String: Any]) {
        guard let event = message["event"] as? String,
              let id = message["id"] as? String
        else {
            return
        }

        if event == "start" {
            guard let rawURL = message["url"] as? String,
                  let url = URL(string: rawURL)
            else {
                return
            }

            let record = XHRRequestRecord(
                id: id,
                kind: message["kind"] as? String ?? "xhr",
                method: (message["method"] as? String ?? "GET").uppercased(),
                url: url.absoluteString,
                host: url.host?.lowercased(),
                pageURL: message["pageURL"] as? String,
                pageHost: (message["pageHost"] as? String)?.lowercased(),
                requestHeaders: Self.stringDictionary(from: message["requestHeaders"]),
                userAgent: message["userAgent"] as? String,
                startedAt: Date(),
                completedAt: nil,
                status: nil,
                responseURL: nil,
                responseBytes: nil,
                jsonType: nil,
                jsonItems: nil,
                jsonShape: nil,
                error: nil
            )

            xhrRecordIndexesByID[id] = xhrRecords.count
            xhrRecords.append(record)
            return
        }

        guard let index = xhrRecordIndexesByID[id],
              xhrRecords.indices.contains(index)
        else {
            return
        }

        xhrRecords[index].completedAt = Date()
        xhrRecords[index].status = Self.intValue(from: message["status"])
        xhrRecords[index].responseURL = message["responseURL"] as? String
        xhrRecords[index].responseBytes = Self.intValue(from: message["responseBytes"])
        xhrRecords[index].jsonType = message["jsonType"] as? String
        xhrRecords[index].jsonItems = Self.intValue(from: message["jsonItems"])
        xhrRecords[index].jsonShape = message["jsonShape"] as? String
        xhrRecords[index].error = message["error"] as? String

        markScreenshotDirty(scheduleAfter: 0.45)
    }

    func recordVisitedURL(_ url: URL, identityID: UUID?) {
        settingsStore.updateLastVisitedURL(url, identityID: identityID)
        historyURLs = settingsStore.settings.historyURLs
        refreshSiteIdentityState()
    }

    func displayXHRJSON(_ response: XHRReplayResponse, from url: URL) {
        let mimeType = response.contentType?
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init) ?? "application/json"

        webView.load(
            response.body,
            mimeType: mimeType,
            characterEncodingName: "utf-8",
            baseURL: url
        )
    }

}
