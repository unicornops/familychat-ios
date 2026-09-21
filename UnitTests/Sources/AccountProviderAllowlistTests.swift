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
        // A wildcard rule is never offered as the server to sign in to, only its suffix as a starting point.
        #expect(appSettings.suggestedAccountProviders == ["safechat.family"])
        #expect(appSettings.defaultServer == "safechat.family")
        
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
}
