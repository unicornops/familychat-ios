//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

@MainActor
struct AppRouteURLParserTests {
    var appSettings: AppSettings
    var appRouteURLParser: AppRouteURLParser
    
    init() {
        appSettings = AppSettings.volatile()
        appRouteURLParser = AppRouteURLParser(appSettings: appSettings)
    }
    
    @Test
    func oAuthCallbackRoute() {
        // Given an OAuth callback for this app.
        let callbackURL = appSettings.oAuthRedirectURL.appending(queryItems: [URLQueryItem(name: "state", value: "12345"),
                                                                              URLQueryItem(name: "code", value: "67890")])
        
        // When parsing that route.
        let route = appRouteURLParser.route(from: callbackURL)
        
        // Then it should be considered a valid OAuth callback.
        #expect(route == .oAuthCallback(url: callbackURL))
    }
    
    @Test
    func oAuthCallbackAppVariantRoute() {
        // Given an OAuth callback for a different app variant.
        let callbackURL = appSettings.oAuthRedirectURL
            .deletingLastPathComponent()
            .appending(component: "family.safechat.nightly")
            .appending(queryItems: [URLQueryItem(name: "state", value: "12345"),
                                    URLQueryItem(name: "code", value: "67890")])
        
        // When parsing that route in this app.
        let route = appRouteURLParser.route(from: callbackURL)
        
        // Then the route shouldn't be considered valid and should be ignored.
        #expect(route == nil)
    }
    
    @Test
    func accountProvisioningLink() throws {
        // Given a plain provisioning link from the control panel (no sign-in code).
        let url = try #require(URL(string: "https://safechat.family/app/login?account_provider=smith.safechat.family&login_hint=mxid:@ana:smith.safechat.family"))
        
        let route = appRouteURLParser.route(from: url)
        
        #expect(route == .accountProvisioningLink(.init(accountProvider: "smith.safechat.family", loginHint: "mxid:@ana:smith.safechat.family")))
    }
    
    @Test
    func accountProvisioningLinkWithSignInCode() throws {
        // Given a provisioning link carrying a sign-in code.
        let url = try #require(URL(string: "https://safechat.family/app/login?account_provider=smith.safechat.family&login_hint=mxid:@ana:smith.safechat.family&hs=Smith.safechat.family&token=syl_abc_DEF-123"))
        
        let route = appRouteURLParser.route(from: url)
        
        // Then the code and its (lower-cased) host are parsed.
        let expected = AccountProvisioningParameters(accountProvider: "smith.safechat.family",
                                                     loginHint: "mxid:@ana:smith.safechat.family",
                                                     hs: "smith.safechat.family",
                                                     token: "syl_abc_DEF-123")
        #expect(route == .accountProvisioningLink(expected))
        #expect(expected.hasSignInCode)
        #expect(expected.signInCodeHomeserverURL == URL(string: "https://smith.safechat.family"))
    }
    
    @Test
    func accountProvisioningLinkViaAppScheme() throws {
        // Given the website's fallback page opening the app through its own scheme with the same host and path.
        let scheme = InfoPlistReader.app.appScheme
        let url = try #require(URL(string: "\(scheme)://safechat.family/app/login?account_provider=smith.safechat.family&hs=smith.safechat.family:8448&token=syl_abc"))
        
        let route = appRouteURLParser.route(from: url)
        
        // Then it behaves exactly like the universal link, an explicit port included.
        #expect(route == .accountProvisioningLink(.init(accountProvider: "smith.safechat.family", loginHint: nil, hs: "smith.safechat.family:8448", token: "syl_abc")))
    }
    
    @Test
    func accountProvisioningLinkDropsIncompleteOrMalformedSignInCodes() throws {
        let plain = AccountProvisioningParameters(accountProvider: "smith.safechat.family", loginHint: nil)
        
        // A token without a host, and a host without a token, are both ignored.
        for query in ["token=syl_abc", "hs=smith.safechat.family"] {
            let url = try #require(URL(string: "https://safechat.family/app/login?account_provider=smith.safechat.family&\(query)"))
            #expect(appRouteURLParser.route(from: url) == .accountProvisioningLink(plain), "\(query)")
        }
        
        // A host that is not a bare hostname drops the code entirely: the token is never sent anywhere odd.
        for hs in ["https%3A%2F%2Fsmith.safechat.family", "smith.safechat.family%2Fpath", "user%40smith.safechat.family", "smith.safechat.family:abc", "-smith.safechat.family"] {
            let url = try #require(URL(string: "https://safechat.family/app/login?account_provider=smith.safechat.family&hs=\(hs)&token=syl_abc"))
            #expect(appRouteURLParser.route(from: url) == .accountProvisioningLink(plain), hs)
        }
    }
    
    @Test
    func accountProvisioningParametersNeverDescribeTheToken() {
        let parameters = AccountProvisioningParameters(accountProvider: "smith.safechat.family", loginHint: nil, hs: "smith.safechat.family", token: "syl_secret")
        
        #expect(!String(describing: parameters).contains("syl_secret"))
        #expect(!String(describing: AppRoute.accountProvisioningLink(parameters)).contains("syl_secret"))
        #expect(parameters.withoutSignInCode == .init(accountProvider: "smith.safechat.family", loginHint: nil))
    }
    
    @Test
    func matrixUserURL() throws {
        let userID = "@test:matrix.org"
        let url = try #require(URL(string: "https://matrix.to/#/\(userID)"))
        
        let route = appRouteURLParser.route(from: url)
        
        #expect(route == .userProfile(userID: userID))
    }
    
    @Test
    func matrixRoomIdentifierURL() throws {
        let id = "!abcdefghijklmnopqrstuvwxyz1234567890:matrix.org"
        let url = try #require(URL(string: "https://matrix.to/#/\(id)"))
        
        let route = appRouteURLParser.route(from: url)
        
        #expect(route == .room(roomID: id, via: []))
    }
    
    @Test
    func webRoomIDURL() throws {
        let id = "!abcdefghijklmnopqrstuvwxyz1234567890:matrix.org"
        let url = try #require(URL(string: "https://app.safechat.family/#/room/\(id)"))
        
        let route = appRouteURLParser.route(from: url)
        
        #expect(route == .room(roomID: id, via: []))
    }
    
    @Test
    func webUserIDURL() throws {
        let id = "@alice:matrix.org"
        let url = try #require(URL(string: "https://app.safechat.family/#/user/\(id)"))
        
        let route = appRouteURLParser.route(from: url)
        
        #expect(route == .userProfile(userID: id))
    }
}
