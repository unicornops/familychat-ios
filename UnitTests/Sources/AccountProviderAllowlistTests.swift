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
        
        // Then family homeservers (a sign-in link's `hs`) are allowed, as a name, a host with port, or a URL.
        #expect(appSettings.isAllowedHomeserverHost("smith.safechat.family"))
        #expect(appSettings.isAllowedHomeserverHost("smith.safechat.family:8448"))
        #expect(appSettings.isAllowedHomeserverHost("https://smith.safechat.family/"))
        #expect(appSettings.isAllowedHomeserverHost(" Smith.SafeChat.Family "))
        
        // And no other homeserver is.
        #expect(!appSettings.isAllowedHomeserverHost("matrix.org"))
        #expect(!appSettings.isAllowedHomeserverHost("smith.ie"))
        #expect(!appSettings.isAllowedHomeserverHost("safechat.family"))
        #expect(!appSettings.isAllowedHomeserverHost("evilsafechat.family"))
        #expect(!appSettings.isAllowedHomeserverHost("https://evil.example/smith.safechat.family"))
    }
    
    @Test
    func onlyTheCanonicalHostIsHandedOn() {
        let appSettings = AppSettings.volatile()
        
        #expect(appSettings.allowedHomeserverHost("smith.safechat.family") == "smith.safechat.family")
        #expect(appSettings.allowedHomeserverHost(" https://Smith.SafeChat.Family/\n") == "smith.safechat.family")
        #expect(appSettings.allowedHomeserverHost("smith.safechat.family:8448") == "smith.safechat.family:8448")
        #expect(appSettings.allowedHomeserverHost("matrix.org") == nil)
        
        // Any canonical server name may be tried (a family's own domain); where it resolves decides the rest.
        #expect(appSettings.accountProviderServerName("smith.ie") == "smith.ie")
        #expect(appSettings.accountProviderServerName(" https://Smith.IE/\n") == "smith.ie")
        #expect(appSettings.accountProviderServerName("smith.ie:8448") == "smith.ie:8448")
        #expect(appSettings.accountProviderServerName("smith.safechat.family") == "smith.safechat.family")
    }
    
    @Test
    func parserDifferentialsAreRefused() {
        // Foundation's URL parser and the SDK's WHATWG parser disagree about these; WHATWG reads `\` as `/`, so the
        // SDK would talk to evil.com. Anything that isn't plainly `hostname[:port]` is refused, as a homeserver and
        // as a server name to discover.
        let appSettings = AppSettings.volatile()
        for input in Self.bypasses {
            #expect(!appSettings.isAllowedHomeserverHost(input), Comment(rawValue: input))
            #expect(appSettings.allowedHomeserverHost(input) == nil, Comment(rawValue: input))
            #expect(appSettings.accountProviderServerName(input) == nil, Comment(rawValue: input))
        }
    }
    
    // MARK: - Resolved homeserver URLs
    
    @Test
    func resolvedHomeserverMustBeAnHTTPSFamilyServer() {
        // Given the app's default configuration (locked to `*.safechat.family`).
        let appSettings = AppSettings.volatile()
        
        // Then any server name is fine when it resolves to a family homeserver over https.
        for url in ["https://smith.safechat.family", "https://smith.safechat.family/", "https://Smith.SafeChat.Family",
                    "https://smith-m2.safechat.family:443/", "https://smith.safechat.family/_matrix/client"] {
            #expect(appSettings.isAllowedHomeserver(serverName: "smith.ie", homeserverURL: url), Comment(rawValue: url))
        }
        
        // And refused when it resolves anywhere else, or anything but plainly.
        let refused = ["https://evil.com",
                       "https://evil.com/",
                       "https://evil.com/smith.safechat.family",
                       "https://evil.com?.safechat.family",
                       "https://evil.com#.safechat.family",
                       "https://evil.com\\.safechat.family",
                       "https://evil.com\\@a.safechat.family",
                       "https://user@smith.safechat.family",
                       "https://evil.com%2F.safechat.family",
                       "https://smith.safechat.family.evil.com",
                       "https://safechat.family",
                       "https://evilsafechat.family",
                       "http://smith.safechat.family",
                       "smith.safechat.family",
                       "//smith.safechat.family",
                       " https://smith.safechat.family",
                       "https://[::1]",
                       "https://127.0.0.1",
                       ""]
        for url in refused {
            #expect(!appSettings.isAllowedHomeserver(serverName: "smith.safechat.family", homeserverURL: url), Comment(rawValue: url))
        }
    }
    
    @Test
    func plainEntriesKeepUpstreamMeaning() {
        // Given an upstream-style configuration with a plain entry.
        let appSettings = AppSettings.volatile()
        appSettings.overrideAccountProviders(["company.com"])
        
        // Then that server may delegate anywhere over https, and no other server name is tried at all.
        #expect(appSettings.isAllowedHomeserver(serverName: "company.com", homeserverURL: "https://matrix.company.com"))
        #expect(!appSettings.isAllowedHomeserver(serverName: "company.com", homeserverURL: "http://matrix.company.com"))
        #expect(!appSettings.isAllowedHomeserver(serverName: "other.com", homeserverURL: "https://matrix.company.com"))
        #expect(appSettings.accountProviderServerName("company.com") == "company.com")
        #expect(appSettings.accountProviderServerName("other.com") == nil)
    }
    
    // MARK: - Provisioning links
    
    @Test
    func customDomainLinkWithSignInCodeIsKept() throws {
        // Given a sign-in link for a family on its own domain.
        let link = AccountProvisioningParameters(accountProvider: "Smith.IE",
                                                 loginHint: "mxid:@kid:smith.ie",
                                                 hs: "smith.safechat.family",
                                                 token: "syl_code")
        
        // Then everything is kept: the code goes to the allowlisted `hs`, the account is on the family's domain.
        let allowed = try #require(link.allowed(by: AppSettings.volatile()))
        #expect(allowed.accountProvider == "smith.ie")
        #expect(allowed.loginHintUserID == "@kid:smith.ie")
        #expect(allowed.hs == "smith.safechat.family")
        #expect(allowed.hasSignInCode)
    }
    
    @Test
    func signInCodeForADisallowedHomeserverIsDropped() throws {
        let link = AccountProvisioningParameters(accountProvider: "smith.ie",
                                                 loginHint: "mxid:@kid:smith.ie",
                                                 hs: "evil.com",
                                                 token: "syl_code")
        
        // Then the code goes nowhere and only the (discovery-checked) password sign-in remains.
        let allowed = try #require(link.allowed(by: AppSettings.volatile()))
        #expect(!allowed.hasSignInCode)
        #expect(allowed.token == nil)
        #expect(allowed.accountProvider == "smith.ie")
        #expect(allowed.loginHint == "mxid:@kid:smith.ie")
    }
    
    @Test
    func linkWithoutCodeIsLeftToDiscovery() throws {
        // A link without a code for any canonical name is kept: `configure` refuses it if it resolves elsewhere.
        let allowed = try #require(AccountProvisioningParameters(accountProvider: "evil.com", loginHint: nil).allowed(by: AppSettings.volatile()))
        #expect(allowed.accountProvider == "evil.com")
    }
    
    @Test
    func loginHintForAnotherServerIsDropped() throws {
        let link = AccountProvisioningParameters(accountProvider: "smith.ie",
                                                 loginHint: "mxid:@kid:evil.com",
                                                 hs: "smith.safechat.family",
                                                 token: "syl_code")
        let allowed = try #require(link.allowed(by: AppSettings.volatile()))
        #expect(allowed.loginHint == nil)
        #expect(allowed.hasSignInCode)
    }
    
    @Test
    func linkParserDifferentialsAreIgnored() {
        let appSettings = AppSettings.volatile()
        for input in Self.bypasses {
            let link = AccountProvisioningParameters(accountProvider: input, loginHint: nil, hs: "smith.safechat.family", token: "syl_code")
            #expect(link.allowed(by: appSettings) == nil, Comment(rawValue: input))
            
            // Nor is a code kept for such an `hs`.
            let codeLink = AccountProvisioningParameters(accountProvider: "smith.ie", loginHint: nil, hs: input, token: "syl_code")
            #expect(codeLink.allowed(by: appSettings)?.hasSignInCode == false, Comment(rawValue: input))
        }
    }
    
    private static let bypasses = ["https://evil.com\\.safechat.family",
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
                                   "smith.safechat.family:8448/path"]
    
    @Test
    func hostsAreAnchoredAtBothEnds() {
        #expect(AppSettings.isValidHostAndPort("smith.safechat.family"))
        #expect(AppSettings.isValidHostAndPort("smith.safechat.family:8448"))
        #expect(!AppSettings.isValidHostAndPort("smith.safechat.family\n"))
        #expect(!AppSettings.isValidHostAndPort("\nsmith.safechat.family"))
        #expect(!AppSettings.isValidHostAndPort("evil.com\nsmith.safechat.family"))
    }
}

private extension AppSettings {
    func overrideAccountProviders(_ accountProviders: [String]) {
        override(accountProviders: accountProviders,
                 allowOtherAccountProviders: false,
                 hideBrandChrome: false,
                 pushGatewayBaseURL: pushGatewayBaseURL,
                 oAuthRedirectURL: oAuthRedirectURL,
                 oAuthClientURIPath: oAuthClientURIPath,
                 websiteURL: websiteURL,
                 logoURL: logoURL,
                 copyrightURL: copyrightURL,
                 acceptableUseURL: acceptableUseURL,
                 privacyURL: privacyURL,
                 encryptionURL: encryptionURL,
                 deviceVerificationURL: deviceVerificationURL,
                 chatBackupDetailsURL: chatBackupDetailsURL,
                 identityPinningViolationDetailsURL: identityPinningViolationDetailsURL,
                 historySharingDetailsURL: historySharingDetailsURL,
                 elementWebHosts: elementWebHosts,
                 accountProvisioningHost: accountProvisioningHost,
                 bugReportApplicationID: bugReportApplicationID,
                 analyticsTermsURL: analyticsTermsURL,
                 mapTilerConfiguration: AppSettings.bundledMapTilerConfiguration)
    }
}
