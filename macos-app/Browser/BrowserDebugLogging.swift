//
//  BrowserDebugLogging.swift
//  macos-app
//

import Foundation

enum BrowserDebugLogging {
    private static let forceDebugLogging = false
    private static let forceDarkModeScriptLogging = false
    private static let forcePerformanceLogging = false

    static var isEnabled: Bool {
        forceDebugLogging || UserDefaults.standard.bool(forKey: "wkdomains.debugLogging")
    }

    static var darkModeScriptEnabled: Bool {
        forceDarkModeScriptLogging
            || isEnabled
            || UserDefaults.standard.bool(forKey: "wkdomains.darkModeDebugLogging")
    }

    static var performanceEnabled: Bool {
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
        guard isEnabled else { return }
        NSLog("%@", message())
    }

    static func performance(_ message: @autoclosure () -> String) {
        guard performanceEnabled else { return }
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
        performance(
            "[wkdomains-debug] perf slow \(label) elapsed=\(String(format: "%.3fs", elapsed))\(detailText.isEmpty ? "" : " \(detailText)")"
        )
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
                performance("[wkdomains-debug] perf main-thread-stall lag=\(String(format: "%.3fs", lag))")
            }
            mainThreadMonitorExpectedFire = now + interval
        }
        mainThreadMonitor = timer
        timer.resume()
        performance("[wkdomains-debug] perf main-thread-monitor started interval=\(String(format: "%.2fs", interval))")
    }
}
