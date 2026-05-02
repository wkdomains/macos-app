//
//  DomainUtilities.swift
//  macos-app
//
//  Created by aa on 5/2/26.
//

import Foundation

enum DomainUtilities {
    static func registrableDomain(from host: String) -> String {
        let normalizedHost = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))

        if normalizedHost == "localhost"
            || normalizedHost.contains(":")
            || normalizedHost.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil
        {
            return normalizedHost
        }

        let labels = normalizedHost.split(separator: ".").map(String.init)
        guard labels.count > 2 else {
            return normalizedHost
        }

        let secondLevelSuffixes: Set<String> = ["ac", "co", "com", "edu", "gov", "net", "org"]
        if labels.last?.count == 2,
           let penultimate = labels.dropLast().last,
           secondLevelSuffixes.contains(penultimate),
           labels.count >= 3
        {
            return labels.suffix(3).joined(separator: ".")
        }

        return labels.suffix(2).joined(separator: ".")
    }
}
