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
///
/// A wildcard rule is judged on the host of the resolved homeserver URL, never on the server name typed or linked:
/// a family on its own domain (Matrix server name `smith.ie`) is served at `<slug>.safechat.family` via `.well-known`,
/// so `smith.ie` is fine as long as it resolves there. See `isAllowedHomeserver(serverName:homeserverURL:)`.
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
    
    /// The server name to hand to `AuthenticationService.configure(for:flow:)` for `input`, or nil when the app may not
    /// even try it.
    ///
    /// When any account provider is allowed the input is returned untouched, as upstream. Otherwise it must be a
    /// canonical `hostname[:port]` (see `canonicalAccountProviderHost(_:)`), and that canonical host is returned, never
    /// the raw input, so the SDK can't read a different host out of it.
    ///
    /// With a wildcard rule (`*.safechat.family`) any canonical host is a candidate: a family on its own domain has
    /// the Matrix server name `smith.ie` and is served at `<slug>.safechat.family` through `.well-known` delegation.
    /// Whether the app may actually sign in there is decided by where the name resolves, which
    /// `isAllowedHomeserver(serverName:homeserverURL:)` checks before any credentials are sent. Without a wildcard rule
    /// the host must be one of the plain entries, as upstream.
    func accountProviderServerName(_ input: String) -> String? {
        if allowOtherAccountProviders {
            return input
        }
        guard let hostAndPort = Self.canonicalAccountProviderHost(input) else {
            return nil
        }
        if hasWildcardAccountProvider {
            return hostAndPort
        }
        return pickableAccountProviders.contains { Self.accountProvider(Self.host(ofHostAndPort: hostAndPort), matches: $0) } ? hostAndPort : nil
    }
    
    /// The homeserver host for `input` when it matches an `accountProviders` entry itself, or nil otherwise.
    ///
    /// Used for the `hs` of a sign-in link, which names the homeserver directly (no discovery) and receives the
    /// sign-in code. When any account provider is allowed the input is returned untouched, as upstream. Otherwise it
    /// must be a canonical `hostname[:port]` (see `canonicalAccountProviderHost(_:)`) matching an entry, and that
    /// canonical host is returned, never the raw input.
    func allowedHomeserverHost(_ input: String) -> String? {
        if allowOtherAccountProviders {
            return input
        }
        guard let hostAndPort = Self.canonicalAccountProviderHost(input) else {
            return nil
        }
        return accountProviders.contains { Self.accountProvider(Self.host(ofHostAndPort: hostAndPort), matches: $0) } ? hostAndPort : nil
    }
    
    /// Whether `input` names a homeserver host that matches an `accountProviders` entry (see `allowedHomeserverHost(_:)`).
    /// Always true when any account provider is allowed.
    func isAllowedHomeserverHost(_ input: String) -> Bool {
        allowedHomeserverHost(input) != nil
    }
    
    /// Whether the app may sign in to the homeserver at `homeserverURL`, the URL the SDK resolved for `serverName`
    /// (after `.well-known` discovery). This is the check that has to pass before any password, sign-in code or OAuth
    /// request is made.
    ///
    /// Always true when any account provider is allowed. Otherwise `homeserverURL` must be `https://` with a plain
    /// `hostname[:port]` authority, and either its host matches a wildcard rule (a custom domain such as `smith.ie`
    /// delegating to `smith.safechat.family` is fine; one delegating anywhere else is not), or `serverName` is itself
    /// one of the plain entries, which keep upstream's meaning of a server the operator trusts.
    func isAllowedHomeserver(serverName: String, homeserverURL: String) -> Bool {
        if allowOtherAccountProviders {
            return true
        }
        guard let host = Self.httpsHost(ofHomeserverURL: homeserverURL) else {
            return false
        }
        let wildcards = accountProviders.filter(Self.isWildcardAccountProvider)
        if wildcards.contains(where: { Self.accountProvider(host, matches: $0) }) {
            return true
        }
        guard let serverHostAndPort = Self.canonicalAccountProviderHost(serverName) else {
            return false
        }
        return pickableAccountProviders.contains { Self.accountProvider(Self.host(ofHostAndPort: serverHostAndPort), matches: $0) }
    }
    
    /// The lower-cased host of an `https://` homeserver URL, or nil when the URL is anything else.
    ///
    /// The authority (everything up to the first `/`) must be a plain `hostname[:port]`: userinfo, `\`, `%`, `?`,
    /// `#`, whitespace, IPv6 literals and other schemes are refused rather than interpreted. An IPv4 address reads as
    /// a hostname here and is returned; it then matches no wildcard rule. Whatever follows the
    /// authority is a path and doesn't affect the host.
    static func httpsHost(ofHomeserverURL url: String) -> String? {
        let value = url.lowercased()
        guard value.hasPrefix("https://") else {
            return nil
        }
        let authority = String(value.dropFirst("https://".count).prefix { $0 != "/" })
        guard isValidHostAndPort(authority) else {
            return nil
        }
        return host(ofHostAndPort: authority)
    }
    
    /// `hostAndPort` without its port.
    private static func host(ofHostAndPort hostAndPort: String) -> String {
        hostAndPort.split(separator: ":", maxSplits: 1).first.map(String.init) ?? hostAndPort
    }
    
    /// An example a user can copy for the wildcard rule: `yourfamily.safechat.family`.
    var exampleAccountProvider: String {
        guard let first = accountProviders.first else {
            return ""
        }
        return Self.isWildcardAccountProvider(first) ? "yourfamily\(first.dropFirst())" : first
    }
}
