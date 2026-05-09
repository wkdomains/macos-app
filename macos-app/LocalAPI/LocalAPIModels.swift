//
//  LocalAPIModels.swift
//  macos-app
//

import Foundation
@preconcurrency import WebKit

enum InspectionError: LocalizedError {
    case noPageLoaded
    case couldNotDecodePageJSON
    case couldNotEncodeDiagnosticJSON
    case invalidNavigationRequest
    case invalidNavigationURL
    case softNavigationRequiresSameOrigin
    case xhrIndexOutOfRange(Int)
    case invalidXHRURL
    case xhrReplayReturnedEmptyBody(Int?)
    case xhrReplayReturnedNonJSON(Int?)

    var errorDescription: String? {
        switch self {
        case .noPageLoaded:
            return "No page is loaded."
        case .couldNotDecodePageJSON:
            return "Could not decode page inspection JSON."
        case .couldNotEncodeDiagnosticJSON:
            return "Could not encode diagnostic JSON."
        case .invalidNavigationRequest:
            return "Provide a JSON body with a url string and optional mode: auto, hard, or soft."
        case .invalidNavigationURL:
            return "Navigation URL must resolve to an http or https URL."
        case .softNavigationRequiresSameOrigin:
            return "Soft navigation is only available for same-origin URLs."
        case .xhrIndexOutOfRange(let index):
            return "No observed XHR request exists at index \(index)."
        case .invalidXHRURL:
            return "The observed XHR request URL is invalid."
        case .xhrReplayReturnedEmptyBody(let statusCode):
            if let statusCode {
                return "The replayed XHR returned an empty body with HTTP \(statusCode)."
            }

            return "The replayed XHR returned an empty body."
        case .xhrReplayReturnedNonJSON(let statusCode):
            if let statusCode {
                return "The replayed XHR did not return JSON with HTTP \(statusCode)."
            }

            return "The replayed XHR did not return JSON."
        }
    }
}

extension RequestedDomain {
    var localStorageOrigins: [URL] {
        var hosts = [host]

        if host.hasPrefix("www.") {
            hosts.append(String(host.dropFirst(4)))
        } else if !isLocalHostLike {
            hosts.append("www.\(host)")
        }

        var urls: [URL] = []
        var seen = Set<String>()
        let schemes = isLocalHostLike ? ["http", "https"] : ["https", "http"]

        for scheme in schemes {
            for host in hosts {
                var components = URLComponents()
                components.scheme = scheme
                components.host = host
                components.port = port
                components.path = "/"

                guard let url = components.url else {
                    continue
                }

                let key = url.absoluteString
                if seen.insert(key).inserted {
                    urls.append(url)
                }
            }
        }

        return urls
    }

    var isLocalHostLike: Bool {
        host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
    }

    func matches(host candidate: String) -> Bool {
        let candidate = candidate.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return candidate == host
            || candidate.hasSuffix(".\(host)")
            || host.hasSuffix(".\(candidate)")
    }
}

struct DomainStorageResponse: Encodable {
    let domain: String
    let cookies: [CookieResponse]
    let localStorage: [LocalStorageOriginResponse]
    let sessionStorage: [SessionStorageOriginResponse]
}

struct XHRRequestsResponse: Encodable {
    let hostname: String
    let activePageURL: String?
    let activePageHost: String?
    let requests: [XHRRequestResponse]
}

struct XHRReplayResponse {
    let body: Data
    let contentType: String?
}

struct PageResponse: Encodable {
    let url: String?
    let title: String?
    let host: String?
    let domain: String?
    let origin: String?
    let viewportMode: String
    let viewportWidth: Int
    let viewportHeight: Int
    let isLoading: Bool
    let canGoBack: Bool
    let canGoForward: Bool
}

struct ConsoleMessagesResponse: Encodable {
    let activePageURL: String?
    let activePageHost: String?
    let captureScope: String
    let capturedLevels: [String]
    let messages: [ConsoleMessageResponse]
}

struct ConsoleMessageResponse: Encodable {
    let id: UUID
    let level: String
    let message: String
    let arguments: [String]
    let pageURL: String?
    let pageHost: String?
    let stack: String?
    let createdAt: Date

    init(record: ConsoleMessageRecord) {
        id = record.id
        level = record.level
        message = record.message
        arguments = record.arguments
        pageURL = record.pageURL
        pageHost = record.pageHost
        stack = record.stack
        createdAt = record.createdAt
    }
}

struct DomainResourcesResponse: Encodable {
    let domain: String?
    let pageHost: String?
    let resources: [DomainResourceResponse]
}

struct DomainResourceResponse: Encodable {
    let url: String
    let path: String
    let status: Int?
    let found: Bool
    let contentType: String?
    let contentLength: Int?
    let sampledBytes: Int
    let bodyPreview: String?
    let error: String?
}

struct XHRRequestResponse: Encodable {
    let id: String
    let kind: String
    let method: String
    let url: String
    let host: String?
    let pageURL: String?
    let pageHost: String?
    let requestHeaders: [String: String]
    let userAgent: String?
    let startedAt: Date
    let completedAt: Date?
    let status: Int?
    let responseURL: String?
    let responseBytes: Int?
    let jsonType: String?
    let jsonItems: Int?
    let jsonShape: String?
    let error: String?

    init(record: XHRRequestRecord) {
        id = record.id
        kind = record.kind
        method = record.method
        url = record.url
        host = record.host
        pageURL = record.pageURL
        pageHost = record.pageHost
        requestHeaders = record.requestHeaders
        userAgent = record.userAgent
        startedAt = record.startedAt
        completedAt = record.completedAt
        status = record.status
        responseURL = record.responseURL
        responseBytes = record.responseBytes
        jsonType = record.jsonType
        jsonItems = record.jsonItems
        jsonShape = record.jsonShape
        error = record.error
    }
}

struct CookieResponse: Encodable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresAt: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool
    let sameSitePolicy: String?

    init(cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expiresAt = cookie.expiresDate
        isSecure = cookie.isSecure
        isHTTPOnly = cookie.isHTTPOnly
        sameSitePolicy = cookie.sameSitePolicy?.rawValue
    }
}

struct LocalStorageOriginResponse: Encodable {
    let origin: String
    let items: [StorageItem]
    let error: String?
}

struct SessionStorageOriginResponse: Encodable {
    let origin: String
    let items: [StorageItem]
    let error: String?
}

struct StorageItem: Codable {
    let key: String
    let value: String?
}

@MainActor
final class LocalStorageReader {
    private let dataStore: WKWebsiteDataStore
    private var sessions: [ObjectIdentifier: LocalStorageSession] = [:]

    init(dataStore: WKWebsiteDataStore) {
        self.dataStore = dataStore
    }

    func readLocalStorage(for origins: [URL], completion: @escaping ([LocalStorageOriginResponse]) -> Void) {
        guard !origins.isEmpty else {
            completion([])
            return
        }

        var pending = origins.count
        var results: [LocalStorageOriginResponse] = []

        for origin in origins {
            var session: LocalStorageSession?
            session = LocalStorageSession(origin: origin, dataStore: dataStore) { [weak self] result in
                if let session {
                    self?.sessions.removeValue(forKey: ObjectIdentifier(session))
                }

                results.append(result)
                pending -= 1

                if pending == 0 {
                    completion(results.sorted { $0.origin < $1.origin })
                }
            }

            if let session {
                sessions[ObjectIdentifier(session)] = session
                session.start()
            }
        }
    }
}

@MainActor
private final class LocalStorageSession: NSObject, WKNavigationDelegate {
    private let origin: URL
    private let webView: WKWebView
    private let completion: (LocalStorageOriginResponse) -> Void
    private var completed = false

    init(origin: URL, dataStore: WKWebsiteDataStore, completion: @escaping (LocalStorageOriginResponse) -> Void) {
        self.origin = origin
        self.completion = completion

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        webView.navigationDelegate = self
    }

    func start() {
        webView.loadHTMLString("<!doctype html><title></title>", baseURL: origin)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        readLocalStorage()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(items: [], error: error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(items: [], error: error.localizedDescription)
    }

    private func readLocalStorage() {
        let script = """
        JSON.stringify(Array.from({ length: localStorage.length }, (_, index) => {
            const key = localStorage.key(index);
            return { key, value: localStorage.getItem(key) };
        }))
        """

        webView.evaluateJavaScript(script) { [weak self] value, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    self.finish(items: [], error: error.localizedDescription)
                    return
                }

                guard let json = value as? String,
                      let data = json.data(using: .utf8),
                      let items = try? JSONDecoder().decode([StorageItem].self, from: data)
                else {
                    self.finish(items: [], error: "Could not decode localStorage.")
                    return
                }

                self.finish(items: items.sorted { $0.key < $1.key }, error: nil)
            }
        }
    }

    private func finish(items: [StorageItem], error: String?) {
        guard !completed else { return }
        completed = true

        var components = URLComponents()
        components.scheme = origin.scheme
        components.host = origin.host
        components.port = origin.port

        completion(
            LocalStorageOriginResponse(
                origin: components.url?.absoluteString ?? origin.absoluteString,
                items: items,
                error: error
            )
        )
    }
}
