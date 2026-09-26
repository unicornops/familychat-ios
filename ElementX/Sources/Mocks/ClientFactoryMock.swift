//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK
import MatrixRustSDKMocks

extension ClientFactoryMock {
    struct Configuration {
        var homeserverClients = [
            "matrix.org": ClientSDKMock(.init()),
            "https://matrix-client.matrix.org": ClientSDKMock(.init()),
            "example.com": ClientSDKMock(.init(serverName: "example.com",
                                               homeserverURL: "https://matrix.example.com",
                                               slidingSyncVersion: .native,
                                               oAuthLoginURL: nil,
                                               supportsOAuthCreatePrompt: false,
                                               supportsPasswordLogin: true)),
            // Family Chat: a sign-in link's `hs`, as the password fallback after a failed sign-in code configures it.
            "https://example.com": ClientSDKMock(.init(serverName: "example.com",
                                                       homeserverURL: "https://example.com",
                                                       slidingSyncVersion: .native,
                                                       oAuthLoginURL: nil,
                                                       supportsOAuthCreatePrompt: false,
                                                       supportsPasswordLogin: true)),
            "company.com": ClientSDKMock(.init(serverName: "company.com",
                                               homeserverURL: "https://matrix.company.com",
                                               slidingSyncVersion: .native,
                                               oAuthLoginURL: "https://auth.company.com/login",
                                               supportsOAuthCreatePrompt: false,
                                               supportsPasswordLogin: false)),
            "server.net": ClientSDKMock(.init(serverName: "server.net",
                                              homeserverURL: "https://matrix.server.net",
                                              slidingSyncVersion: .native,
                                              oAuthLoginURL: nil,
                                              supportsOAuthCreatePrompt: false,
                                              supportsPasswordLogin: false)),
            "secure.gov": ClientSDKMock(.init(serverName: "secure.gov",
                                              homeserverURL: "https://ess.secure.gov",
                                              slidingSyncVersion: .native,
                                              oAuthLoginURL: "https://auth.secure.gov/login",
                                              supportsOAuthCreatePrompt: false,
                                              supportsPasswordLogin: false,
                                              elementWellKnown: "{\"version\":1,\"enforce_element_pro\":true}")),
            // Family Chat: a family homeserver, and a family on its own domain whose `.well-known` delegates to it.
            "smith.safechat.family": ClientSDKMock(.init(serverName: "smith.safechat.family",
                                                         homeserverURL: "https://smith.safechat.family",
                                                         slidingSyncVersion: .native,
                                                         oAuthLoginURL: nil,
                                                         supportsOAuthCreatePrompt: false,
                                                         supportsPasswordLogin: true)),
            "smith.ie": ClientSDKMock(.init(serverName: "smith.ie",
                                            homeserverURL: "https://smith.safechat.family/",
                                            slidingSyncVersion: .native,
                                            oAuthLoginURL: nil,
                                            supportsOAuthCreatePrompt: false,
                                            supportsPasswordLogin: true,
                                            validCredentials: (username: "@kid:smith.ie", password: "12345678"))),
            // A domain whose `.well-known` points at a homeserver outside `*.safechat.family`.
            "evil.com": ClientSDKMock(.init(serverName: "evil.com",
                                            homeserverURL: "https://evil.com",
                                            slidingSyncVersion: .native,
                                            oAuthLoginURL: nil,
                                            supportsOAuthCreatePrompt: false,
                                            supportsPasswordLogin: true,
                                            validCredentials: (username: "@kid:evil.com", password: "12345678")))
        ]
    }
    
    convenience init(_ configuration: Configuration) {
        self.init()
        
        makeAuthenticationClientHomeserverAddressSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksClosure = { address, _, _, _, _, _ in
            guard let client = configuration.homeserverClients[address] else {
                throw ClientBuildError.ServerUnreachable(message: "Not a known homeserver.")
            }
            return client
        }
        
        makeInMemoryClientHomeserverAddressClientSessionDelegateAppSettingsAppHooksClosure = { address, _, _, _ in
            guard let client = configuration.homeserverClients[address] else {
                throw ClientBuildError.ServerUnreachable(message: "Not a known homeserver.")
            }
            return client
        }
        
        makeAppClientCredentialsClientSessionDelegateAppSettingsAppHooksClosure = { credentials, _, _, _ in
            ClientSDKMock(.init(userID: credentials.userID))
        }
        
        makeNSEClientCredentialsRoomIDClientSessionDelegateAppSettingsAppHooksClosure = { credentials, _, _, _, _ in
            ClientSDKMock(.init(userID: credentials.userID))
        }
    }
}
