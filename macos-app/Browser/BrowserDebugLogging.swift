//
//  BrowserDebugLogging.swift
//  macos-app
//

import Foundation

struct BrowserTimingEvent: Encodable {
    let id: Int
    let source: String
    let category: String
    let label: String
    let message: String
    let detail: String?
    let pageURL: String?
    let pageHost: String?
    let elapsedMilliseconds: Double?
    let sessionElapsedMilliseconds: Double
    let uptimeMilliseconds: Double
    let createdAt: Date
}

struct BrowserTimingSummary: Encodable {
    let source: String
    let category: String
    let label: String
    let count: Int
    let totalElapsedMilliseconds: Double
    let averageElapsedMilliseconds: Double
    let maxElapsedMilliseconds: Double
    let latestElapsedMilliseconds: Double
    let latestDetail: String?
    let latestAt: Date
}

struct BrowserTimingResponse: Encodable {
    let activePageURL: String?
    let activePageHost: String?
    let sessionID: UUID
    let sessionPageURL: String?
    let sessionPageHost: String?
    let sessionStartedAt: Date
    let sessionElapsedMilliseconds: Double
    let generatedAt: Date
    let eventCount: Int
    let elapsedEventCount: Int
    let summary: [BrowserTimingSummary]
    let events: [BrowserTimingEvent]
}

enum BrowserDebugLogging {
    private static let forceDebugLogging = false
    private static let forceDarkModeScriptLogging = false
    private static let forcePerformanceLogging = false
    private static let maxTimingEvents = 1000

    private static let timingLock = NSLock()
    private static var nextTimingEventID = 1
    private static var timingSessionID = UUID()
    private static var timingSessionStartedAt = Date()
    private static var timingSessionStartedUptime = timestamp()
    private static var timingSessionPageURL: String?
    private static var timingSessionPageHost: String?
    private static var timingEvents: [BrowserTimingEvent] = []

    static var isEnabled: Bool {
        forceDebugLogging || UserDefaults.standard.bool(forKey: "wkdomains.debugLogging")
    }

    static var darkModeScriptEnabled: Bool {
        forceDarkModeScriptLogging
            || isEnabled
            || UserDefaults.standard.bool(forKey: "wkdomains.darkModeDebugLogging")
    }

    static var performanceEnabled: Bool {
        timingEnabled || xcodePerformanceLoggingEnabled
    }

    static var timingEnabled: Bool {
        if let explicitValue = UserDefaults.standard.object(forKey: "wkdomains.timingEnabled") as? Bool {
            return explicitValue
        }

        return true
    }

    private static var xcodePerformanceLoggingEnabled: Bool {
        if forcePerformanceLogging {
            return true
        }

        if let explicitValue = UserDefaults.standard.object(forKey: "wkdomains.performanceDebugLogging") as? Bool {
            return explicitValue
        }

        return false
    }

    private static var mainThreadMonitor: DispatchSourceTimer?
    private static var mainThreadMonitorExpectedFire: TimeInterval = 0

    static func timestamp() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    static func formatElapsed(since startedAt: TimeInterval) -> String {
        String(format: "%.3fs", timestamp() - startedAt)
    }

    static func log(_ message: @autoclosure () -> String) {
        let text = message()
        recordDebugMessage(text)
        guard isEnabled else { return }
        NSLog("%@", text)
    }

    static func performance(_ message: @autoclosure () -> String) {
        let text = message()
        recordPerformanceMessage(text)
        guard xcodePerformanceLoggingEnabled else { return }
        NSLog("%@", text)
    }

    static func xcodePerformance(_ message: @autoclosure () -> String) {
        guard xcodePerformanceLoggingEnabled else { return }
        NSLog("%@", message())
    }

    static func logSlowOperation(
        _ label: String,
        since startedAt: TimeInterval,
        threshold: TimeInterval = 0.05,
        details: @autoclosure () -> String = ""
    ) {
        guard performanceEnabled else { return }
        let elapsed = timestamp() - startedAt
        guard elapsed >= threshold else { return }
        let detailText = details()
        let message = "[wkdomains-debug] perf slow \(label) elapsed=\(String(format: "%.3fs", elapsed))\(detailText.isEmpty ? "" : " \(detailText)")"
        recordTiming(
            source: "native",
            category: "slow-operation",
            label: label,
            message: message,
            detail: detailText,
            pageURL: nil,
            pageHost: nil,
            elapsedMilliseconds: elapsed * 1000
        )
        xcodePerformance(message)
    }

    static func startMainThreadStallMonitor() {
        guard performanceEnabled, mainThreadMonitor == nil else { return }

        let interval: TimeInterval = 0.25
        mainThreadMonitorExpectedFire = timestamp() + interval

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(25))
        timer.setEventHandler {
            let now = timestamp()
            let lag = now - mainThreadMonitorExpectedFire
            if lag >= 0.15 {
                let message = "[wkdomains-debug] perf main-thread-stall lag=\(String(format: "%.3fs", lag))"
                recordTiming(
                    source: "native",
                    category: "main-thread",
                    label: "main-thread-stall",
                    message: message,
                    detail: nil,
                    pageURL: nil,
                    pageHost: nil,
                    elapsedMilliseconds: lag * 1000
                )
                xcodePerformance(message)
            }
            mainThreadMonitorExpectedFire = now + interval
        }
        mainThreadMonitor = timer
        timer.resume()
        performance("[wkdomains-debug] perf main-thread-monitor started interval=\(String(format: "%.2fs", interval))")
    }

    static func startTimingSession(pageURL: String?, pageHost: String?, reason: String) {
        guard timingEnabled else { return }
        let startedAt = Date()
        let startedUptime = timestamp()
        let normalizedHost = pageHost?.lowercased()

        timingLock.lock()
        timingSessionID = UUID()
        timingSessionStartedAt = startedAt
        timingSessionStartedUptime = startedUptime
        timingSessionPageURL = pageURL
        timingSessionPageHost = normalizedHost
        timingEvents.removeAll(keepingCapacity: true)
        nextTimingEventID = 1
        appendTimingEventLocked(
            source: "native",
            category: "session",
            label: reason,
            message: "[wkdomains-timing] session \(reason)",
            detail: nil,
            pageURL: pageURL,
            pageHost: normalizedHost,
            elapsedMilliseconds: nil,
            createdAt: startedAt,
            uptime: startedUptime
        )
        timingLock.unlock()
    }

    static func recordPagePerformance(
        level: String,
        message: String,
        arguments: [String],
        pageURL: String?,
        pageHost: String?
    ) {
        guard performanceEnabled else { return }
        let marker = arguments.first ?? message
        let isProxy = marker.contains("wkdomains-dark-proxy-perf")
        let label = arguments.indices.contains(1) ? arguments[1] : "page-performance"
        let elapsed = arguments
            .compactMap { elapsedMilliseconds(in: $0) }
            .first ?? elapsedMilliseconds(in: message)
        let detail = arguments.indices.contains(3) ? arguments[3] : nil

        recordTiming(
            source: "page",
            category: isProxy ? "dark-mode-proxy" : "dark-mode",
            label: label,
            message: message,
            detail: detail,
            pageURL: pageURL,
            pageHost: pageHost?.lowercased(),
            elapsedMilliseconds: elapsed
        )
    }

    static func recordTimingEvent(
        category: String,
        label: String,
        message: String,
        detail: String? = nil,
        pageURL: String? = nil,
        pageHost: String? = nil,
        elapsedMilliseconds: Double? = nil
    ) {
        recordTiming(
            source: "native",
            category: category,
            label: label,
            message: message,
            detail: detail,
            pageURL: pageURL,
            pageHost: pageHost?.lowercased(),
            elapsedMilliseconds: elapsedMilliseconds
        )
    }

    static func timingResponse(activePageURL: String?, activePageHost: String?) -> BrowserTimingResponse {
        timingLock.lock()
        let sessionID = timingSessionID
        let sessionPageURL = timingSessionPageURL
        let sessionPageHost = timingSessionPageHost
        let sessionStartedAt = timingSessionStartedAt
        let sessionStartedUptime = timingSessionStartedUptime
        let events = timingEvents
        timingLock.unlock()

        let elapsedEvents = events.filter { $0.elapsedMilliseconds != nil }
        let summaries = timingSummaries(for: elapsedEvents)
        return BrowserTimingResponse(
            activePageURL: activePageURL,
            activePageHost: activePageHost?.lowercased(),
            sessionID: sessionID,
            sessionPageURL: sessionPageURL,
            sessionPageHost: sessionPageHost,
            sessionStartedAt: sessionStartedAt,
            sessionElapsedMilliseconds: max(0, (timestamp() - sessionStartedUptime) * 1000),
            generatedAt: Date(),
            eventCount: events.count,
            elapsedEventCount: elapsedEvents.count,
            summary: summaries,
            events: events
        )
    }

    private static func recordDebugMessage(_ message: String) {
        guard timingEnabled, !message.contains("path=/api/v1/timing") else { return }
        let elapsed = elapsedMilliseconds(in: message)
        recordTiming(
            source: "native",
            category: elapsed == nil ? "event" : "timing",
            label: label(for: message, fallback: "native-event"),
            message: message,
            detail: nil,
            pageURL: nil,
            pageHost: nil,
            elapsedMilliseconds: elapsed
        )
    }

    private static func recordPerformanceMessage(_ message: String) {
        guard performanceEnabled else { return }
        recordTiming(
            source: "native",
            category: "performance",
            label: label(for: message, fallback: "native-performance"),
            message: message,
            detail: nil,
            pageURL: nil,
            pageHost: nil,
            elapsedMilliseconds: elapsedMilliseconds(in: message)
        )
    }

    private static func recordTiming(
        source: String,
        category: String,
        label: String,
        message: String,
        detail: String?,
        pageURL: String?,
        pageHost: String?,
        elapsedMilliseconds: Double?
    ) {
        guard timingEnabled else { return }
        let createdAt = Date()
        let uptime = timestamp()

        timingLock.lock()
        appendTimingEventLocked(
            source: source,
            category: category,
            label: label,
            message: message,
            detail: detail,
            pageURL: pageURL,
            pageHost: pageHost,
            elapsedMilliseconds: elapsedMilliseconds,
            createdAt: createdAt,
            uptime: uptime
        )
        timingLock.unlock()
    }

    private static func appendTimingEventLocked(
        source: String,
        category: String,
        label: String,
        message: String,
        detail: String?,
        pageURL: String?,
        pageHost: String?,
        elapsedMilliseconds: Double?,
        createdAt: Date,
        uptime: TimeInterval
    ) {
        let event = BrowserTimingEvent(
            id: nextTimingEventID,
            source: source,
            category: category,
            label: clip(label, limit: 120),
            message: clip(message, limit: 1600),
            detail: detail.map { clip($0, limit: 800) },
            pageURL: pageURL.map { clip($0, limit: 1200) },
            pageHost: pageHost?.lowercased(),
            elapsedMilliseconds: elapsedMilliseconds.flatMap { $0.isFinite ? $0 : nil },
            sessionElapsedMilliseconds: max(0, (uptime - timingSessionStartedUptime) * 1000),
            uptimeMilliseconds: uptime * 1000,
            createdAt: createdAt
        )
        nextTimingEventID += 1
        timingEvents.append(event)
        if timingEvents.count > maxTimingEvents {
            timingEvents.removeFirst(timingEvents.count - maxTimingEvents)
        }
    }

    private static func timingSummaries(for events: [BrowserTimingEvent]) -> [BrowserTimingSummary] {
        struct Bucket {
            let source: String
            let category: String
            let label: String
            var count: Int
            var total: Double
            var max: Double
            var latest: Double
            var latestDetail: String?
            var latestAt: Date
        }

        var buckets: [String: Bucket] = [:]
        for event in events {
            guard let elapsed = event.elapsedMilliseconds else { continue }
            let key = [event.source, event.category, event.label].joined(separator: "\u{1F}")
            if var bucket = buckets[key] {
                bucket.count += 1
                bucket.total += elapsed
                bucket.max = max(bucket.max, elapsed)
                bucket.latest = elapsed
                bucket.latestDetail = event.detail
                bucket.latestAt = event.createdAt
                buckets[key] = bucket
            } else {
                buckets[key] = Bucket(
                    source: event.source,
                    category: event.category,
                    label: event.label,
                    count: 1,
                    total: elapsed,
                    max: elapsed,
                    latest: elapsed,
                    latestDetail: event.detail,
                    latestAt: event.createdAt
                )
            }
        }

        return buckets.values
            .map { bucket in
                BrowserTimingSummary(
                    source: bucket.source,
                    category: bucket.category,
                    label: bucket.label,
                    count: bucket.count,
                    totalElapsedMilliseconds: bucket.total,
                    averageElapsedMilliseconds: bucket.total / Double(max(1, bucket.count)),
                    maxElapsedMilliseconds: bucket.max,
                    latestElapsedMilliseconds: bucket.latest,
                    latestDetail: bucket.latestDetail,
                    latestAt: bucket.latestAt
                )
            }
            .sorted {
                if $0.totalElapsedMilliseconds == $1.totalElapsedMilliseconds {
                    return $0.maxElapsedMilliseconds > $1.maxElapsedMilliseconds
                }

                return $0.totalElapsedMilliseconds > $1.totalElapsedMilliseconds
            }
    }

    private static func elapsedMilliseconds(in text: String) -> Double? {
        elapsedValue(after: "elapsed", in: text)
            ?? elapsedValue(after: "lag", in: text)
    }

    private static func elapsedValue(after key: String, in text: String) -> Double? {
        guard let range = text.range(of: "\(key)=") else { return nil }
        var index = range.upperBound
        var number = ""

        while index < text.endIndex {
            let character = text[index]
            if character.isNumber || character == "." || character == "-" {
                number.append(character)
                index = text.index(after: index)
            } else {
                break
            }
        }

        guard let value = Double(number), value.isFinite else { return nil }
        var unit = ""
        while index < text.endIndex {
            let character = text[index]
            if character.isLetter {
                unit.append(character)
                index = text.index(after: index)
            } else {
                break
            }
        }

        if unit == "s" {
            return value * 1000
        }

        return value
    }

    private static func label(for message: String, fallback: String) -> String {
        if let range = message.range(of: "perf slow ") {
            return token(in: message, after: range.upperBound) ?? fallback
        }
        if message.contains("main-thread-stall") {
            return "main-thread-stall"
        }
        if let range = message.range(of: "local-api eval ") {
            let name = token(in: message, after: range.upperBound) ?? "eval"
            if message.contains(" decode-fail ") { return "local-api.eval.\(name).decode-fail" }
            if message.contains(" fail ") { return "local-api.eval.\(name).fail" }
            if message.contains(" slow ") { return "local-api.eval.\(name).slow" }
            if message.contains(" done ") { return "local-api.eval.\(name).done" }
            return "local-api.eval.\(name)"
        }
        if let range = message.range(of: "local-api ") {
            let name = token(in: message, after: range.upperBound) ?? "request"
            return "local-api.\(name)"
        }
        if let range = message.range(of: "navigation ") {
            return "navigation.\(token(in: message, after: range.upperBound) ?? "event")"
        }
        if let range = message.range(of: "xhr ") {
            return "xhr.\(token(in: message, after: range.upperBound) ?? "event")"
        }
        if let range = message.range(of: "[wkdomains-dark-perf] ") {
            return token(in: message, after: range.upperBound) ?? "dark-mode"
        }
        if let range = message.range(of: "[wkdomains-dark-proxy-perf] ") {
            return token(in: message, after: range.upperBound) ?? "dark-mode-proxy"
        }

        return fallback
    }

    private static func token(in text: String, after start: String.Index) -> String? {
        var index = start
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }

        guard index < text.endIndex else { return nil }
        let tokenStart = index
        while index < text.endIndex, !text[index].isWhitespace {
            index = text.index(after: index)
        }

        return String(text[tokenStart..<index])
    }

    private static func clip(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
    }
}
