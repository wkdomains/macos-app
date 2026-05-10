//
//  LocalAPIWebsiteDataReader+XHR.swift
//  macos-app
//

import Foundation
@preconcurrency import WebKit

extension WebsiteDataReader {
    func readXHRRequests(for domain: RequestedDomain) -> XHRRequestsResponse {
        let requests = browser.sortedXHRRequests(for: domain.host)
            .map(XHRRequestResponse.init(record:))

        return XHRRequestsResponse(
            hostname: domain.host,
            activePageURL: browser.webView.url?.absoluteString,
            activePageHost: browser.webView.url?.host,
            requests: requests
        )
    }

    func readXHRRequestsForCurrentPage() -> Result<XHRRequestsResponse, Error> {
        do {
            return .success(readXHRRequests(for: try currentPageDomain()))
        } catch {
            return .failure(error)
        }
    }

    func replayXHRRequestForCurrentPage(
        at index: Int,
        completion: @escaping (Result<XHRReplayResponse, Error>) -> Void
    ) {
        do {
            let domain = try currentPageDomain()
            let requests = readXHRRequests(for: domain).requests

            guard requests.indices.contains(index) else {
                throw InspectionError.xhrIndexOutOfRange(index)
            }

            let xhr = requests[index]
            guard let url = URL(string: xhr.url) else {
                throw InspectionError.invalidXHRURL
            }

            let dataStore = browser.webView.configuration.websiteDataStore
            dataStore.httpCookieStore.getAllCookies { cookies in
                Task { @MainActor in
                    let cookieHeader = Self.cookieHeader(for: url, from: cookies)

                    do {
                        let response = try await Self.fetchXHRJSON(
                            xhr: xhr,
                            url: url,
                            cookieHeader: cookieHeader
                        )
                        completion(.success(response))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    static func fetchXHRJSON(
        xhr: XHRRequestResponse,
        url: URL,
        cookieHeader: String?
    ) async throws -> XHRReplayResponse {
        var request = URLRequest(url: url)
        request.httpMethod = xhr.method
        request.timeoutInterval = 30

        for (name, value) in xhr.requestHeaders {
            guard shouldReplayHeader(name) else {
                continue
            }

            request.setValue(value, forHTTPHeaderField: name)
        }

        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        }

        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(xhr.userAgent ?? BotTerminalModel.llmsUserAgent, forHTTPHeaderField: "User-Agent")
        }

        if let cookieHeader, !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        if let pageURL = xhr.pageURL {
            if request.value(forHTTPHeaderField: "Referer") == nil {
                request.setValue(pageURL, forHTTPHeaderField: "Referer")
            }

            if request.value(forHTTPHeaderField: "Origin") == nil,
               let origin = URL(string: pageURL).map(Self.originString(from:)) {
                request.setValue(origin, forHTTPHeaderField: "Origin")
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode

        guard !data.isEmpty else {
            throw InspectionError.xhrReplayReturnedEmptyBody(statusCode)
        }

        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw InspectionError.xhrReplayReturnedNonJSON(statusCode)
        }

        let responseContentType = httpResponse?.value(forHTTPHeaderField: "Content-Type")
        let contentType: String
        if responseContentType?.lowercased().contains("json") == true {
            contentType = responseContentType ?? "application/json; charset=utf-8"
        } else {
            contentType = "application/json; charset=utf-8"
        }

        return XHRReplayResponse(
            body: data,
            contentType: contentType
        )
    }

    private static func shouldReplayHeader(_ name: String) -> Bool {
        switch name.lowercased() {
        case "accept-encoding",
            "connection",
            "content-length",
            "cookie",
            "host",
            "proxy-authorization",
            "te",
            "trailer",
            "transfer-encoding",
            "upgrade":
            return false
        default:
            return true
        }
    }
}
