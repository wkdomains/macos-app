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

    func writeCurrentPageFilesToTemporaryDirectory() {
        let directoryURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            showAlert(message: "Could Not Create Directory", detail: error.localizedDescription)
            return
        }

        let path = directoryURL.path
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)

        Task { @MainActor [weak self] in
            await self?.writeCurrentPageFiles(to: directoryURL)
        }
    }

    private func writeCurrentPageFiles(to directoryURL: URL) async {
        let dataReader = WebsiteDataReader(browser: self)
        var failures: [String] = []

        do {
            let consoleData = try Self.encodedAPIJSON(dataReader.readConsoleMessages())
            try consoleData.write(to: directoryURL.appendingPathComponent("console.json"), options: .atomic)
        } catch {
            failures.append("console.json: \(error.localizedDescription)")
        }

        let screenshotResult: Result<Data, Error> = await withCheckedContinuation { continuation in
            dataReader.readScreenshot { result in
                continuation.resume(returning: result)
            }
        }

        switch screenshotResult {
        case .success(let pngData):
            do {
                try pngData.write(to: directoryURL.appendingPathComponent("screenshot.png"), options: .atomic)
            } catch {
                failures.append("screenshot.png: \(error.localizedDescription)")
            }
        case .failure(let error):
            failures.append("screenshot.png: \(error.localizedDescription)")
        }

        let domResult: Result<Any, Error> = await withCheckedContinuation { continuation in
            dataReader.readDOM { result in
                continuation.resume(returning: result)
            }
        }

        do {
            let domData: Data
            switch domResult {
            case .success(let response):
                domData = try Self.encodedJSONObject(response)
            case .failure(let error):
                failures.append("dom.json: \(error.localizedDescription)")
                domData = try Self.encodedAPIJSON(APIErrorResponse(error: error.localizedDescription))
            }

            try domData.write(to: directoryURL.appendingPathComponent("dom.json"), options: .atomic)
        } catch {
            failures.append("dom.json: \(error.localizedDescription)")
        }

        if !failures.isEmpty {
            showAlert(message: "Some Files Could Not Be Written", detail: failures.joined(separator: "\n"))
        }
    }

    private static func encodedAPIJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private static func encodedJSONObject(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
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

        let level = record.level.lowercased()
        if level == "error" || level == "warn" || record.message.contains("wkdomains") {
            let line = "[wkdomains-debug] console level=\(record.level) host=\(record.pageHost ?? "nil") url=\(record.pageURL ?? "nil") message=\(record.message)"
            if record.message.contains("wkdomains-dark-perf") || record.message.contains("wkdomains-dark-proxy-perf") {
                BrowserDebugLogging.recordPagePerformance(
                    level: record.level,
                    message: record.message,
                    arguments: record.arguments,
                    pageURL: record.pageURL,
                    pageHost: record.pageHost
                )
                BrowserDebugLogging.xcodePerformance(line)
            } else {
                BrowserDebugLogging.log(line)
            }
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
            if record.host == webView.url?.host?.lowercased() {
                BrowserDebugLogging.log("[wkdomains-debug] xhr start id=\(id) method=\(record.method) url=\(record.url)")
            }
            return
        }

        guard let index = xhrRecordIndexesByID[id],
              xhrRecords.indices.contains(index)
        else {
            return
        }

        let completedAt = Date()
        xhrRecords[index].completedAt = completedAt
        xhrRecords[index].status = Self.intValue(from: message["status"])
        xhrRecords[index].responseURL = message["responseURL"] as? String
        xhrRecords[index].responseBytes = Self.intValue(from: message["responseBytes"])
        xhrRecords[index].jsonType = message["jsonType"] as? String
        xhrRecords[index].jsonItems = Self.intValue(from: message["jsonItems"])
        xhrRecords[index].jsonShape = message["jsonShape"] as? String
        xhrRecords[index].error = message["error"] as? String

        let record = xhrRecords[index]
        if record.host == webView.url?.host?.lowercased() {
            BrowserDebugLogging.log(
                "[wkdomains-debug] xhr done id=\(id) status=\(record.status.map(String.init) ?? "nil") bytes=\(record.responseBytes.map(String.init) ?? "nil") error=\(record.error ?? "nil") url=\(record.url)"
            )
        }
        BrowserDebugLogging.recordTimingEvent(
            category: "network",
            label: Self.xhrTimingLabel(for: record),
            message: "[wkdomains-timing] xhr \(record.method) \(record.url)",
            detail: "status=\(record.status.map(String.init) ?? "nil") bytes=\(record.responseBytes.map(String.init) ?? "nil") error=\(record.error ?? "nil")",
            pageURL: record.pageURL,
            pageHost: record.pageHost,
            elapsedMilliseconds: completedAt.timeIntervalSince(record.startedAt) * 1000
        )

        markScreenshotDirty(scheduleAfter: 0.45)
    }

    private static func xhrTimingLabel(for record: XHRRequestRecord) -> String {
        guard let url = URL(string: record.url),
              let host = url.host?.lowercased()
        else {
            return "xhr.\(record.method)"
        }

        let path = url.path.isEmpty ? "/" : url.path
        return "xhr.\(record.method) \(host)\(path)"
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
