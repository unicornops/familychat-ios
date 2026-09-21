//
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// Family Chat runs one homeserver per family under `<slug>.safechat.family`, so `accountProviders` accepts
/// wildcard entries: `*.suffix` matches any subdomain of `suffix` (one or more labels), never the bare suffix.
/// Matching ignores case. A plain entry matches exactly as upstream.
nonisolated extension AppSettings {
    /// Whether `pattern` is a wildcard entry.
    static func isWildcardAccountProvider(_ pattern: String) -> Bool {
        pattern.hasPrefix("*.")
    }
    
    /// Whether `serverName` matches one `accountProviders` entry.
    static func accountProvider(_ serverName: String, matches pattern: String) -> Bool {
        let serverName = serverName.lowercased()
        let pattern = pattern.lowercased()
        if isWildcardAccountProvider(pattern) {
            let suffix = String(pattern.dropFirst()) // keep the leading dot so `evilsafechat.family` never matches
            return serverName.count > suffix.count && serverName.hasSuffix(suffix)
        }
        return serverName == pattern
    }
    
    /// The account providers a user can be offered directly: every entry that isn't a wildcard rule.
    var pickableAccountProviders: [String] {
        accountProviders.filter { !Self.isWildcardAccountProvider($0) }
    }
    
    /// Whether `accountProviders` contains a wildcard rule, in which case the user has to type their own server.
    var hasWildcardAccountProvider: Bool {
        accountProviders.contains(where: Self.isWildcardAccountProvider)
    }
    
    /// Whether the app may sign in to `serverName` (a server name, a host, or a URL whose host is checked).
    /// Always true when any account provider is allowed.
    func isAllowedAccountProvider(_ serverName: String) -> Bool {
        if allowOtherAccountProviders {
            return true
        }
        let host = Self.host(from: serverName)
        return accountProviders.contains { Self.accountProvider(host, matches: $0) }
    }
    
    /// An example a user can copy for the wildcard rule: `yourfamily.safechat.family`.
    var exampleAccountProvider: String {
        guard let first = accountProviders.first else {
            return ""
        }
        return Self.isWildcardAccountProvider(first) ? "yourfamily\(first.dropFirst())" : first
    }
    
    /// The host part of a server name, `host:port` or URL, lower-cased.
    private static func host(from serverName: String) -> String {
        let trimmed = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return (URL(string: withScheme)?.host() ?? trimmed).lowercased()
    }
}
