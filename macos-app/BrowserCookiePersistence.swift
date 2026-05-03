//
//  BrowserCookiePersistence.swift
//  macos-app
//
//  Created by aa on 5/3/26.
//

import Foundation
import WebKit

final class BrowserCookiePersistence: NSObject {
    private let directoryURL: URL
    private var profileID = "default"
    private var observedCookieStore: WKHTTPCookieStore?
    private var saveTask: Task<Void, Never>?
    private var isRestoring = false

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func attach(to dataStore: WKWebsiteDataStore, identityID: UUID?, completion: @escaping () -> Void) {
        saveTask?.cancel()
        if let observedCookieStore {
            observedCookieStore.remove(self)
            saveCookies(from: observedCookieStore)
        }

        profileID = Self.profileID(for: identityID)
        let cookieStore = dataStore.httpCookieStore
        observedCookieStore = cookieStore
        cookieStore.add(self)

        restoreCookies(into: cookieStore, completion: completion)
    }

    func saveNow() {
        saveTask?.cancel()
        guard let observedCookieStore else { return }
        saveCookies(from: observedCookieStore)
    }

    private func scheduleSave(from cookieStore: WKHTTPCookieStore) {
        guard !isRestoring else { return }

        saveTask?.cancel()
        saveTask = Task { [weak self, weak cookieStore] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled,
                  let self,
                  let cookieStore
            else {
                return
            }

            self.saveCookies(from: cookieStore)
        }
    }

    private func saveCookies(from cookieStore: WKHTTPCookieStore) {
        let profileID = self.profileID
        cookieStore.getAllCookies { [directoryURL] cookies in
            do {
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )

                let data = try NSKeyedArchiver.archivedData(
                    withRootObject: cookies,
                    requiringSecureCoding: true
                )
                try data.write(to: Self.cookieArchiveURL(in: directoryURL, profileID: profileID), options: .atomic)
            } catch {
                NSLog("Could not persist browser cookies: \(error.localizedDescription)")
            }
        }
    }

    private func restoreCookies(into cookieStore: WKHTTPCookieStore, completion: @escaping () -> Void) {
        let cookies = loadCookies()
        guard !cookies.isEmpty else {
            completion()
            return
        }

        isRestoring = true
        let group = DispatchGroup()

        for cookie in cookies {
            guard !cookie.isExpired else { continue }

            group.enter()
            cookieStore.setCookie(cookie) {
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self, weak cookieStore] in
            self?.isRestoring = false
            if let cookieStore {
                self?.scheduleSave(from: cookieStore)
            }
            completion()
        }
    }

    private func loadCookies() -> [HTTPCookie] {
        let url = Self.cookieArchiveURL(in: directoryURL, profileID: profileID)
        guard let data = try? Data(contentsOf: url) else { return [] }

        do {
            let allowedClasses: [AnyClass] = [
                NSArray.self,
                HTTPCookie.self,
                NSDate.self,
                NSString.self,
                NSNumber.self,
                NSURL.self
            ]
            return try NSKeyedUnarchiver.unarchivedObject(
                ofClasses: allowedClasses,
                from: data
            ) as? [HTTPCookie] ?? []
        } catch {
            NSLog("Could not restore browser cookies: \(error.localizedDescription)")
            return []
        }
    }

    private static let defaultProfileID = "default"

    private static func profileID(for identityID: UUID?) -> String {
        identityID?.uuidString.lowercased() ?? defaultProfileID
    }

    private static func cookieArchiveURL(in directoryURL: URL, profileID: String) -> URL {
        directoryURL.appendingPathComponent("cookies-\(profileID).archive")
    }
}

extension BrowserCookiePersistence: WKHTTPCookieStoreObserver {
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        scheduleSave(from: cookieStore)
    }
}

private extension HTTPCookie {
    var isExpired: Bool {
        guard let expiresDate else { return false }
        return expiresDate <= Date()
    }
}
