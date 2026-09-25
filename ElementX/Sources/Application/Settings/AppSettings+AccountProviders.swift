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
    
    /// DNS hostname labels (lower-case), optionally followed by a port. Anchored with `\A` and `\z` so that nothing,
    /// not even a trailing newline, can follow; `\`, `@`, `%`, `/`, `?`, `#` and whitespace can never match.
    static func isValidHostAndPort(_ value: String) -> Bool {
        let label = "[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?"
        let pattern = "\\A\(label)(\\.\(label))*(:[0-9]{1,5})?\\z"
        return value.range(of: pattern, options: .regularExpression) != nil
    }
    
    /// The canonical `hostname[:port]` (lower-cased) that `input` names, or nil when it is anything else.
    ///
    /// Accepts a bare host, optionally with one leading `https://` and one trailing `/`, and nothing more. The input
    /// is deliberately not parsed as a URL: Foundation and the SDK's WHATWG parser disagree about inputs such as
    /// `https://evil.com\.safechat.family` (WHATWG reads `\` as `/`, so the host is `evil.com`) or
    /// `evil.com\@a.safechat.family`, so anything that isn't plainly a host is refused rather than interpreted.
    static func canonicalAccountProviderHost(_ input: String) -> String? {
        var value = Substring(input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        if value.hasPrefix("https://") {
            value = value.dropFirst("https://".count)
        }
        if value.hasSuffix("/") {
            value = value.dropLast()
        }
        let host = String(value)
        return isValidHostAndPort(host) ? host : nil
    }
    
    /// The account providers a user can be offered directly: every entry that isn't a wildcard rule.
    var pickableAccountProviders: [String] {
        accountProviders.filter { !Self.isWildcardAccountProvider($0) }
    }
    
    /// Whether `accountProviders` contains a wildcard rule, in which case the user has to type their own server.
    var hasWildcardAccountProvider: Bool {
        accountProviders.contains(where: Self.isWildcardAccountProvider)
    }
    
    /// The suffixes of the wildcard rules (`*.safechat.family` → `safechat.family`).
    var wildcardAccountProviderSuffixes: [String] {
        accountProviders.filter(Self.isWildcardAccountProvider).map { String($0.dropFirst(2)).lowercased() }
    }
    
    /// The server to hand to `AuthenticationService.configure(for:flow:)` for `input`, or nil when the app may not
    /// sign in there.
    ///
    /// When any account provider is allowed the input is returned untouched, as upstream. Otherwise it must be a
    /// canonical `hostname[:port]` (see `canonicalAccountProviderHost(_:)`) matching an `accountProviders` entry, and
    /// that canonical host is returned, never the raw input, so the SDK can't read a different host out of it.
    func allowedAccountProvider(_ input: String) -> String? {
        if allowOtherAccountProviders {
            return input
        }
        guard let hostAndPort = Self.canonicalAccountProviderHost(input) else {
            return nil
        }
        let host = hostAndPort.split(separator: ":", maxSplits: 1).first.map(String.init) ?? hostAndPort
        return accountProviders.contains { Self.accountProvider(host, matches: $0) } ? hostAndPort : nil
    }
    
    /// Whether the app may sign in to `input` (see `allowedAccountProvider(_:)`). Always true when any account
    /// provider is allowed.
    func isAllowedAccountProvider(_ input: String) -> Bool {
        allowedAccountProvider(input) != nil
    }
    
    /// An example a user can copy for the wildcard rule: `yourfamily.safechat.family`.
    var exampleAccountProvider: String {
        guard let first = accountProviders.first else {
            return ""
        }
        return Self.isWildcardAccountProvider(first) ? "yourfamily\(first.dropFirst())" : first
    }
}
