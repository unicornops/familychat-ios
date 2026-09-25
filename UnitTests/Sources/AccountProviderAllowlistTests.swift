//
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

/// The Family Chat wildcard rules for `AppSettings.accountProviders` (`*.safechat.family`).
@MainActor
struct AccountProviderAllowlistTests {
    @Test
    func wildcardMatchesSubdomainsOnly() {
        #expect(AppSettings.accountProvider("smith.safechat.family", matches: "*.safechat.family"))
        #expect(AppSettings.accountProvider("deep.smith.safechat.family", matches: "*.safechat.family"))
        #expect(AppSettings.accountProvider("Smith.SafeChat.Family", matches: "*.safechat.family"))
        #expect(!AppSettings.accountProvider("safechat.family", matches: "*.safechat.family"))
        #expect(!AppSettings.accountProvider("evilsafechat.family", matches: "*.safechat.family"))
        #expect(!AppSettings.accountProvider("smith.safechat.family.evil.example", matches: "*.safechat.family"))
    }
    
    @Test
    func plainEntryMatchesExactly() {
        #expect(AppSettings.accountProvider("matrix.org", matches: "Matrix.org"))
        #expect(!AppSettings.accountProvider("beta.matrix.org", matches: "matrix.org"))
    }
    
    @Test
    func defaultSettingsAllowFamilyServersOnly() {
        // Given the app's default configuration (locked to `*.safechat.family`).
        let appSettings = AppSettings.volatile()
        #expect(appSettings.allowOtherAccountProviders == false)
        #expect(appSettings.hasWildcardAccountProvider)
        #expect(appSettings.pickableAccountProviders.isEmpty)
        #expect(appSettings.exampleAccountProvider == "yourfamily.safechat.family")
        // A wildcard rule is never offered as the server to sign in to, and neither is its bare suffix.
        #expect(appSettings.wildcardAccountProviderSuffixes == ["safechat.family"])
        #expect(appSettings.defaultServer == "")
        
        // Then family servers are allowed, as a name, a host with port, or a URL.
        #expect(appSettings.isAllowedAccountProvider("smith.safechat.family"))
        #expect(appSettings.isAllowedAccountProvider("smith.safechat.family:8448"))
        #expect(appSettings.isAllowedAccountProvider("https://smith.safechat.family/"))
        #expect(appSettings.isAllowedAccountProvider(" Smith.SafeChat.Family "))
        
        // And nothing else is.
        #expect(!appSettings.isAllowedAccountProvider("matrix.org"))
        #expect(!appSettings.isAllowedAccountProvider("safechat.family"))
        #expect(!appSettings.isAllowedAccountProvider("evilsafechat.family"))
        #expect(!appSettings.isAllowedAccountProvider("https://evil.example/smith.safechat.family"))
    }
    
    @Test
    func onlyTheCanonicalHostIsHandedOn() {
        let appSettings = AppSettings.volatile()
        
        #expect(appSettings.allowedAccountProvider("smith.safechat.family") == "smith.safechat.family")
        #expect(appSettings.allowedAccountProvider(" https://Smith.SafeChat.Family/\n") == "smith.safechat.family")
        #expect(appSettings.allowedAccountProvider("smith.safechat.family:8448") == "smith.safechat.family:8448")
        #expect(appSettings.allowedAccountProvider("matrix.org") == nil)
    }
    
    @Test
    func parserDifferentialsAreRefused() {
        // Foundation's URL parser and the SDK's WHATWG parser disagree about these; WHATWG reads `\` as `/`, so the
        // SDK would talk to evil.com. Anything that isn't plainly `hostname[:port]` is refused.
        let appSettings = AppSettings.volatile()
        let bypasses = [
            "https://evil.com\\.safechat.family",
            "evil.com\\.safechat.family",
            "http://evil.com\\@a.safechat.family",
            "evil.com\\@a.safechat.family",
            "user@smith.safechat.family",
            "https://user@smith.safechat.family",
            "evil.com%2F.safechat.family",
            "evil.com/.safechat.family",
            "evil.com?.safechat.family",
            "evil.com#.safechat.family",
            "evil.com .safechat.family",
            "http://smith.safechat.family",
            "https://https://smith.safechat.family",
            "smith.safechat.family//",
            "smith.safechat.family\ninjected",
            "smith.safechat.family:8448/path"
        ]
        for input in bypasses {
            #expect(!appSettings.isAllowedAccountProvider(input), Comment(rawValue: input))
            #expect(appSettings.allowedAccountProvider(input) == nil, Comment(rawValue: input))
        }
    }
    
    @Test
    func hostsAreAnchoredAtBothEnds() {
        #expect(AppSettings.isValidHostAndPort("smith.safechat.family"))
        #expect(AppSettings.isValidHostAndPort("smith.safechat.family:8448"))
        #expect(!AppSettings.isValidHostAndPort("smith.safechat.family\n"))
        #expect(!AppSettings.isValidHostAndPort("\nsmith.safechat.family"))
        #expect(!AppSettings.isValidHostAndPort("evil.com\nsmith.safechat.family"))
    }
}
