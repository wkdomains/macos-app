//
//  LocalAPIHTTP.swift
//  macos-app
//

import Foundation

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    init?(data: Data) {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: delimiter),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8),
              let requestLine = headerText.components(separatedBy: "\r\n").first
        else {
            return nil
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else {
            return nil
        }

        method = parts[0].uppercased()

        let target = parts[1]
        if let components = URLComponents(string: target) {
            path = components.percentEncodedPath.removingPercentEncoding ?? components.path
        } else {
            path = target
        }

        var parsedHeaders: [String: String] = [:]
        for line in headerText.components(separatedBy: "\r\n").dropFirst() {
            let headerParts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard headerParts.count == 2 else { continue }

            parsedHeaders[headerParts[0].lowercased()] = headerParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        headers = parsedHeaders
        body = data[headerRange.upperBound...]
    }

    var originIsAllowed: Bool {
        guard let origin = headers["origin"],
              let originURL = URL(string: origin),
              let host = originURL.host?.lowercased()
        else {
            return true
        }

        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    var xhrReplayIndex: Int? {
        let prefix = "/api/v1/xhr/"
        guard path.hasPrefix(prefix) else {
            return nil
        }

        return Int(path.dropFirst(prefix.count))
    }
}

struct RequestedDomain {
    let host: String
    let port: Int?

    init?(url: URL) {
        guard let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              !host.isEmpty
        else {
            return nil
        }

        self.host = host
        port = url.port
    }
}

enum HTTPStatus: Int {
    case ok = 200
    case accepted = 202
    case badRequest = 400
    case notFound = 404
    case methodNotAllowed = 405
    case serviceUnavailable = 503

    var reason: String {
        switch self {
        case .ok:
            return "OK"
        case .accepted:
            return "Accepted"
        case .badRequest:
            return "Bad Request"
        case .notFound:
            return "Not Found"
        case .methodNotAllowed:
            return "Method Not Allowed"
        case .serviceUnavailable:
            return "Service Unavailable"
        }
    }
}

struct APIErrorResponse: Encodable {
    let error: String
}
