//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import ElementX
import Foundation
import MatrixRustSDKMocks
import Testing

@MainActor
struct AuthenticationServiceTests {
    var client: ClientSDKMock!
    var encryption: EncryptionSDKMock!
    var userSessionStore: UserSessionStoreMock!
    var encryptionKeyProvider: MockEncryptionKeyProvider!
    var service: AuthenticationService!
    var clientFactory: ClientFactoryMock!
    var homeserverClients: [String: ClientSDKMock] = [:]
    
    @Test
    mutating func passwordLogin() async throws {
        try await setup(serverAddress: "example.com")
        
        switch await service.configure(for: "example.com", flow: .login) {
        case .success:
            break
        case .failure(let error):
            Issue.record("Unexpected failure: \(error)")
        }
        
        #expect(service.flow == .login)
        #expect(service.homeserver.value == .mockBasicServer)
        
        switch await service.login(username: "alice", password: "12345678", initialDeviceName: nil, deviceID: nil) {
        case .success:
            #expect(client.loginUsernamePasswordInitialDeviceNameDeviceIdCallsCount == 1)
            #expect(userSessionStore.userSessionForSessionDirectoriesPassphraseCallsCount == 1)
            #expect(userSessionStore.userSessionForSessionDirectoriesPassphraseReceivedArguments?.passphrase ==
                encryptionKeyProvider.generateKey().base64EncodedString())
        case .failure(let error):
            Issue.record("Unexpected failure: \(error)")
        }
    }
    
    @Test
    mutating func configureLoginWithOAuth() async throws {
        try await setup()
        
        try await service.configure(for: "matrix.org", flow: .login).get()
        
        #expect(service.flow == .login)
        #expect(service.homeserver.value == .mockMatrixDotOrg)
    }
    
    @Test
    mutating func configureRegisterWithOAuth() async throws {
        try await setup()
        
        try await service.configure(for: "matrix.org", flow: .register).get()
        
        #expect(service.flow == .register)
        #expect(service.homeserver.value == .mockMatrixDotOrg)
    }
    
    @Test
    @MainActor
    mutating func configureRegisterNoSupport() async throws {
        let homeserverAddress = "example.com"
        try await setup(serverAddress: homeserverAddress)
        
        try await #require(throws: AuthenticationServiceError.registrationNotSupported) {
            try await service.configure(for: homeserverAddress, flow: .register).get()
        }
        
        #expect(service.flow == .login)
        // Family Chat: the default `*.safechat.family` rule offers no server, the user types their family's.
        #expect(service.homeserver.value == .init(address: "", loginMode: .unknown))
    }
    
    @Test
    @MainActor
    mutating func classicAppAccountSecretsBundleIsUsed() async throws {
        // Given an authentication service with an Element Classic account for Alice.
        try await setup(classicAppAccounts: [.mockAlice])
        try await service.configure(for: "matrix.org", flow: .login).get()
        #expect(service.flow == .login)
        #expect(service.classicAppAccount?.state.availableSecrets == .complete)
        
        // When logging in as Alice.
        _ = try await service.login(username: "alice", password: "12345678", initialDeviceName: nil, deviceID: nil).get()
        #expect(client.loginUsernamePasswordInitialDeviceNameDeviceIdCallsCount == 1)
        
        // Then Alice's secrets from Element Classic should be imported.
        #expect(encryption.importSecretsBundleSecretsBundleCalled)
    }
    
    @Test
    @MainActor
    mutating func classicAppAccountSecretsBundleIsIgnoredWhenUnavailable() async throws {
        // Given an authentication service with an Element Classic account for Alice
        // which isn't configured with any available secrets.
        try await setup(classicAppAccounts: [.mockAlice], availableSecrets: .unavailable)
        try await service.configure(for: "matrix.org", flow: .login).get()
        #expect(service.flow == .login)
        #expect(service.classicAppAccount?.state.availableSecrets == .unavailable)
        
        // When logging in as Alice.
        _ = try await service.login(username: "alice", password: "12345678", initialDeviceName: nil, deviceID: nil).get()
        #expect(client.loginUsernamePasswordInitialDeviceNameDeviceIdCallsCount == 1)
        
        // Then an attempt to import Alice's secrets from Element Classic must not be made.
        #expect(!encryption.importSecretsBundleSecretsBundleCalled)
    }
    
    @Test
    @MainActor
    mutating func classicAppAccountSecretsBundleIsIgnoredForDifferentUser() async throws {
        // Given an authentication service with an Element Classic account for Dan.
        try await setup(classicAppAccounts: [.mockDan])
        try await service.configure(for: "matrix.org", flow: .login).get()
        #expect(service.flow == .login)
        #expect(service.classicAppAccount?.state.availableSecrets == .complete)
        
        // When logging in as Alice
        _ = try await service.login(username: "alice", password: "12345678", initialDeviceName: nil, deviceID: nil).get()
        #expect(client.loginUsernamePasswordInitialDeviceNameDeviceIdCallsCount == 1)
        
        // Then Dan's secrets from Element Calssic should not be imported into Alice's client.
        #expect(!encryption.importSecretsBundleSecretsBundleCalled)
    }
    
    @Test
    mutating func signInCodeLogin() async throws {
        // Given a family homeserver and a sign-in code it accepts.
        let exchanger = LoginTokenExchangerMock(.init(result: .success(.mockAna)))
        try await setup(serverAddress: "https://smith.safechat.family", loginTokenExchanger: exchanger)
        
        // When redeeming the code without any prior server configuration.
        let result = await service.loginWithToken("syl_code",
                                                  homeserverURL: "https://smith.safechat.family",
                                                  accountProvider: "smith.safechat.family",
                                                  expectedUserID: "@ana:smith.safechat.family",
                                                  initialDeviceName: "Family Chat iOS")
        
        // Then the code went to that homeserver, the credentials were restored into the client and a session was created.
        switch result {
        case .success:
            #expect(exchanger.exchangeCallsCount == 1)
            #expect(exchanger.exchangeReceivedArguments?.token == "syl_code")
            #expect(exchanger.exchangeReceivedArguments?.homeserverURL == "https://smith.safechat.family")
            #expect(exchanger.exchangeReceivedArguments?.initialDeviceName == "Family Chat iOS")
            #expect(client.restoreSessionSessionCallsCount == 1)
            #expect(client.restoreSessionSessionReceivedSession?.accessToken == "syt_access")
            #expect(client.restoreSessionSessionReceivedSession?.userId == "@ana:smith.safechat.family")
            #expect(client.restoreSessionSessionReceivedSession?.homeserverUrl == "https://smith.safechat.family")
            #expect(client.loginUsernamePasswordInitialDeviceNameDeviceIdCallsCount == 0)
            #expect(userSessionStore.userSessionForSessionDirectoriesPassphraseCallsCount == 1)
            #expect(service.homeserver.value.address == "smith.safechat.family")
            #expect(exchanger.logoutCallsCount == 0)
            #expect(!service.isRedeemingSignInCode)
        case .failure(let error):
            Issue.record("Unexpected failure: \(error)")
        }
    }
    
    @Test
    mutating func signInCodeRejected() async throws {
        // Given a family homeserver that refuses the code (used or expired).
        let exchanger = LoginTokenExchangerMock(.init(result: .failure(.rejected(errcode: "M_FORBIDDEN"))))
        try await setup(serverAddress: "https://smith.safechat.family", loginTokenExchanger: exchanger)
        
        // When redeeming it.
        let result = await service.loginWithToken("syl_code",
                                                  homeserverURL: "https://smith.safechat.family",
                                                  accountProvider: "smith.safechat.family",
                                                  expectedUserID: "@ana:smith.safechat.family",
                                                  initialDeviceName: nil)
        
        // Then the failure is reported as invalid credentials and nothing was restored or stored.
        try await #require(throws: AuthenticationServiceError.invalidCredentials) { try result.get() }
        #expect(client.restoreSessionSessionCallsCount == 0)
        #expect(userSessionStore.userSessionForSessionDirectoriesPassphraseCallsCount == 0)
    }
    
    @Test
    mutating func signInCodeUnreachableHomeserver() async throws {
        // Given a family homeserver that cannot be reached.
        let exchanger = LoginTokenExchangerMock(.init(result: .failure(.network(URLError(.notConnectedToInternet)))))
        try await setup(serverAddress: "https://smith.safechat.family", loginTokenExchanger: exchanger)
        
        let result = await service.loginWithToken("syl_code",
                                                  homeserverURL: "https://smith.safechat.family",
                                                  accountProvider: "smith.safechat.family",
                                                  expectedUserID: "@ana:smith.safechat.family",
                                                  initialDeviceName: nil)
        
        try await #require(throws: AuthenticationServiceError.failedLoggingIn) { try result.get() }
        #expect(userSessionStore.userSessionForSessionDirectoriesPassphraseCallsCount == 0)
    }
    
    @Test
    mutating func signInCodeForAnotherAccountIsDiscarded() async throws {
        // Given a code that the homeserver redeems for another account than the link's login hint named.
        let exchanger = LoginTokenExchangerMock(.init(result: .success(.mock(userID: "@mallory:smith.safechat.family"))))
        try await setup(serverAddress: "https://smith.safechat.family", loginTokenExchanger: exchanger)
        
        let result = await service.loginWithToken("syl_code",
                                                  homeserverURL: "https://smith.safechat.family",
                                                  accountProvider: "smith.safechat.family",
                                                  expectedUserID: "@ana:smith.safechat.family",
                                                  initialDeviceName: nil)
        
        // Then the session is refused and logged out on the homeserver, never restored or stored.
        try await #require(throws: AuthenticationServiceError.signInCodeAccountMismatch) { try result.get() }
        #expect(exchanger.logoutCallsCount == 1)
        #expect(exchanger.logoutReceivedArguments?.accessToken == "syt_access")
        #expect(exchanger.logoutReceivedArguments?.homeserverURL == "https://smith.safechat.family")
        #expect(client.restoreSessionSessionCallsCount == 0)
        #expect(userSessionStore.userSessionForSessionDirectoriesPassphraseCallsCount == 0)
    }
    
    @Test
    mutating func signInCodeWithoutHintMustStayOnTheAccountProvider() async throws {
        // Given a link without a login hint whose code signs in to an account on another server.
        let exchanger = LoginTokenExchangerMock(.init(result: .success(.mock(userID: "@ana:evil.example"))))
        try await setup(serverAddress: "https://smith.safechat.family", loginTokenExchanger: exchanger)
        
        let result = await service.loginWithToken("syl_code",
                                                  homeserverURL: "https://smith.safechat.family",
                                                  accountProvider: "smith.safechat.family",
                                                  expectedUserID: nil,
                                                  initialDeviceName: nil)
        
        try await #require(throws: AuthenticationServiceError.signInCodeAccountMismatch) { try result.get() }
        #expect(exchanger.logoutCallsCount == 1)
        #expect(userSessionStore.userSessionForSessionDirectoriesPassphraseCallsCount == 0)
    }
    
    @Test
    mutating func signInCodeWithRefreshTokenIsDiscarded() async throws {
        // Given a homeserver that unexpectedly hands out a refresh token.
        let exchanger = LoginTokenExchangerMock(.init(result: .success(.mock(userID: "@ana:smith.safechat.family", refreshToken: "syr_refresh"))))
        try await setup(serverAddress: "https://smith.safechat.family", loginTokenExchanger: exchanger)
        
        let result = await service.loginWithToken("syl_code",
                                                  homeserverURL: "https://smith.safechat.family",
                                                  accountProvider: "smith.safechat.family",
                                                  expectedUserID: "@ana:smith.safechat.family",
                                                  initialDeviceName: nil)
        
        // Then the session it can't keep is logged out again rather than left behind.
        try await #require(throws: AuthenticationServiceError.sessionTokenRefreshNotSupported) { try result.get() }
        #expect(exchanger.logoutCallsCount == 1)
        #expect(userSessionStore.userSessionForSessionDirectoriesPassphraseCallsCount == 0)
    }
    
    @Test
    mutating func signInCodesAreRedeemedOneAtATime() async throws {
        // Given a redemption in flight.
        let exchanger = LoginTokenExchangerMock(.init(result: .success(.mockAna)))
        try await setup(serverAddress: "https://smith.safechat.family", loginTokenExchanger: exchanger)
        let service = try #require(self.service)
        var secondResult: Result<UserSessionProtocol, AuthenticationServiceError>?
        exchanger.exchangeWillAnswer = {
            #expect(service.isRedeemingSignInCode)
            // When a second code arrives meanwhile.
            secondResult = await service.loginWithToken("syl_other",
                                                        homeserverURL: "https://smith.safechat.family",
                                                        accountProvider: "smith.safechat.family",
                                                        expectedUserID: nil,
                                                        initialDeviceName: nil)
        }
        
        let result = await service.loginWithToken("syl_code",
                                                  homeserverURL: "https://smith.safechat.family",
                                                  accountProvider: "smith.safechat.family",
                                                  expectedUserID: "@ana:smith.safechat.family",
                                                  initialDeviceName: nil)
        
        // Then the second one is refused without being sent, and the first one completes.
        #expect(throws: AuthenticationServiceError.failedLoggingIn) { try secondResult?.get() }
        #expect(exchanger.exchangeCallsCount == 1)
        _ = try result.get()
        #expect(!service.isRedeemingSignInCode)
    }
    
    // MARK: - Custom domains (family-chat#254)
    
    @Test
    mutating func customDomainSignInCodeRedeemsAgainstTheHomeserver() async throws {
        // Given the app locked to *.safechat.family and a link for a family on its own domain: the code is for
        // `hs=smith.safechat.family`, the account is `@kid:smith.ie`.
        let exchanger = LoginTokenExchangerMock(.init(result: .success(.mock(userID: "@kid:smith.ie"))))
        try await setup(serverAddress: "https://smith.safechat.family", loginTokenExchanger: exchanger, allowOtherAccountProviders: false)
        
        // When redeeming it.
        let result = await service.loginWithToken("syl_code",
                                                  homeserverURL: "https://smith.safechat.family",
                                                  accountProvider: "smith.ie",
                                                  expectedUserID: "@kid:smith.ie",
                                                  initialDeviceName: nil)
        
        // Then the code went to `hs`, the custom-domain account was accepted and the family's domain is remembered.
        _ = try result.get()
        #expect(exchanger.exchangeReceivedArguments?.homeserverURL == "https://smith.safechat.family")
        #expect(client.restoreSessionSessionReceivedSession?.userId == "@kid:smith.ie")
        #expect(exchanger.logoutCallsCount == 0)
        #expect(service.homeserver.value.address == "smith.ie")
    }
    
    @Test
    mutating func customDomainSignInCodeWithoutHintAcceptsTheFamilyDomain() async throws {
        // Given a custom-domain link without a login hint.
        let exchanger = LoginTokenExchangerMock(.init(result: .success(.mock(userID: "@kid:smith.ie"))))
        try await setup(serverAddress: "https://smith.safechat.family", loginTokenExchanger: exchanger, allowOtherAccountProviders: false)
        
        let result = await service.loginWithToken("syl_code",
                                                  homeserverURL: "https://smith.safechat.family",
                                                  accountProvider: "smith.ie",
                                                  expectedUserID: nil,
                                                  initialDeviceName: nil)
        
        // Then an account on the family's domain (the link's `account_provider`, not `hs`) is accepted.
        _ = try result.get()
        #expect(exchanger.logoutCallsCount == 0)
    }
    
    @Test
    mutating func customDomainSignInCodeForAnotherAccountIsDiscarded() async throws {
        // Given custom-domain links whose code signs in to another account than the link named.
        let cases: [(userID: String, expectedUserID: String?)] = [("@mallory:smith.ie", "@kid:smith.ie"),
                                                                  // Without a hint the server must be `account_provider`, not `hs`.
                                                                  ("@kid:smith.safechat.family", nil),
                                                                  ("@kid:evil.com", nil)]
        for testCase in cases {
            let exchanger = LoginTokenExchangerMock(.init(result: .success(.mock(userID: testCase.userID))))
            try await setup(serverAddress: "https://smith.safechat.family", loginTokenExchanger: exchanger, allowOtherAccountProviders: false)
            
            let result = await service.loginWithToken("syl_code",
                                                      homeserverURL: "https://smith.safechat.family",
                                                      accountProvider: "smith.ie",
                                                      expectedUserID: testCase.expectedUserID,
                                                      initialDeviceName: nil)
            
            // Then the session is logged out again and never stored.
            #expect(throws: AuthenticationServiceError.signInCodeAccountMismatch, Comment(rawValue: testCase.userID)) { try result.get() }
            #expect(exchanger.logoutCallsCount == 1, Comment(rawValue: testCase.userID))
            #expect(client.restoreSessionSessionCallsCount == 0, Comment(rawValue: testCase.userID))
            #expect(userSessionStore.userSessionForSessionDirectoriesPassphraseCallsCount == 0, Comment(rawValue: testCase.userID))
        }
    }
    
    @Test
    mutating func customDomainResolvingToAFamilyServerIsAccepted() async throws {
        // Given the app locked to *.safechat.family and `smith.ie` whose `.well-known` points at smith.safechat.family.
        try await setup(serverAddress: "smith.ie", allowOtherAccountProviders: false)
        
        // When configuring it and signing in with the full Matrix ID.
        try await service.configure(for: "smith.ie", flow: .login).get()
        #expect(service.homeserver.value == .init(address: "smith.ie", loginMode: .password))
        _ = try await service.login(username: "@kid:smith.ie", password: "12345678", initialDeviceName: nil, deviceID: nil).get()
        
        // Then the password went to that client.
        #expect(client.loginUsernamePasswordInitialDeviceNameDeviceIdCallsCount == 1)
        #expect(client.loginUsernamePasswordInitialDeviceNameDeviceIdReceivedArguments?.username == "@kid:smith.ie")
    }
    
    @Test
    mutating func domainResolvingOutsideTheAllowlistIsRefusedBeforeLogin() async throws {
        // Given the app locked to *.safechat.family and `evil.com` resolving to https://evil.com.
        try await setup(serverAddress: "evil.com", allowOtherAccountProviders: false)
        
        // When configuring it.
        let result = await service.configure(for: "evil.com", flow: .login)
        
        // Then it is refused right after discovery: the homeserver isn't even asked for its login flows.
        #expect(throws: AuthenticationServiceError.homeserverNotAllowed) { try result.get() }
        #expect(client.homeserverLoginDetailsCallsCount == 0)
        #expect(service.homeserver.value.loginMode == .unknown)
        
        // And a password login attempted anyway never reaches it, and neither does an OAuth request.
        await #expect(throws: AuthenticationServiceError.failedLoggingIn) {
            try await service.login(username: "@kid:evil.com", password: "12345678", initialDeviceName: nil, deviceID: nil).get()
        }
        #expect(client.loginUsernamePasswordInitialDeviceNameDeviceIdCallsCount == 0)
        _ = await service.urlForOAuthLogin(loginHint: nil)
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesCallsCount == 0)
    }
    
    @Test
    mutating func refusedDomainDoesNotReplaceTheConfiguredServer() async throws {
        // Given a family server that is configured already, whose stores exist on disk.
        try await setup(serverAddress: "evil.com", allowOtherAccountProviders: false)
        let familyClient = try #require(homeserverClients["smith.safechat.family"])
        try await service.configure(for: "smith.safechat.family", flow: .login).get()
        let familyDirectories = try #require(clientFactory.makeAuthenticationClientHomeserverAddressSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksReceivedArguments?.sessionDirectories)
        try FileManager.default.createDirectory(at: familyDirectories.dataDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: familyDirectories.cacheDirectory, withIntermediateDirectories: true)
        defer { familyDirectories.delete() }
        
        // When the user then enters a domain that resolves elsewhere, and a server without any usable login.
        await #expect(throws: AuthenticationServiceError.homeserverNotAllowed) { try await service.configure(for: "evil.com", flow: .login).get() }
        await #expect(throws: AuthenticationServiceError.loginNotSupported) { try await service.configure(for: "server.net", flow: .login).get() }
        
        // Then the family server stays configured, and its stores weren't deleted.
        #expect(service.homeserver.value.address == "smith.safechat.family")
        #expect(FileManager.default.directoryExists(at: familyDirectories.dataDirectory))
        #expect(FileManager.default.directoryExists(at: familyDirectories.cacheDirectory))
        
        // And a password login goes to the family server with those stores, never to evil.com.
        _ = try await service.login(username: "alice", password: "12345678", initialDeviceName: nil, deviceID: nil).get()
        #expect(client.loginUsernamePasswordInitialDeviceNameDeviceIdCallsCount == 0)
        #expect(familyClient.loginUsernamePasswordInitialDeviceNameDeviceIdCallsCount == 1)
        #expect(userSessionStore.userSessionForSessionDirectoriesPassphraseReceivedArguments?.sessionDirectories == familyDirectories)
    }
    
    @Test
    mutating func loginMovingTheClientOutsideTheAllowlistIsRefused() async throws {
        // Given a family server whose login response points the client elsewhere (`well_known.m.homeserver`).
        try await setup(serverAddress: "smith.safechat.family", allowOtherAccountProviders: false)
        try await service.configure(for: "smith.safechat.family", flow: .login).get()
        let familyClient = try #require(client)
        familyClient.loginUsernamePasswordInitialDeviceNameDeviceIdClosure = { [weak familyClient] _, _, _, _ in
            familyClient?.homeserverReturnValue = "https://evil.com"
            familyClient?.userIdReturnValue = "@alice:smith.safechat.family"
        }
        
        // When signing in.
        let result = await service.login(username: "alice", password: "12345678", initialDeviceName: nil, deviceID: nil)
        
        // Then the new session is logged out again and never stored.
        #expect(throws: AuthenticationServiceError.homeserverNotAllowed) { try result.get() }
        #expect(familyClient.logoutCallsCount == 1)
        #expect(userSessionStore.userSessionForSessionDirectoriesPassphraseCallsCount == 0)
    }
    
    @Test
    mutating func signInCodeSessionMovedOutsideTheAllowlistIsDiscarded() async throws {
        // Given a sign-in code whose restored session ends up pointing outside the allowlist.
        let exchanger = LoginTokenExchangerMock(.init(result: .success(.mockAna)))
        try await setup(serverAddress: "https://smith.safechat.family", loginTokenExchanger: exchanger, allowOtherAccountProviders: false)
        let familyClient = try #require(client)
        familyClient.restoreSessionSessionClosure = { [weak familyClient] _ in
            familyClient?.homeserverReturnValue = "https://evil.com"
        }
        
        let result = await service.loginWithToken("syl_code",
                                                  homeserverURL: "https://smith.safechat.family",
                                                  accountProvider: "smith.safechat.family",
                                                  expectedUserID: "@ana:smith.safechat.family",
                                                  initialDeviceName: nil)
        
        // Then the session is logged out and never stored.
        #expect(throws: AuthenticationServiceError.homeserverNotAllowed) { try result.get() }
        #expect(familyClient.logoutCallsCount == 1)
        #expect(exchanger.logoutCallsCount == 1)
        #expect(userSessionStore.userSessionForSessionDirectoriesPassphraseCallsCount == 0)
    }
    
    @Test
    mutating func qrCodeForADisallowedServerIsRefused() async throws {
        // Given the app locked to *.safechat.family and a QR code from a device signed in to evil.com.
        try await setup(serverAddress: "evil.com", allowOtherAccountProviders: false)
        
        // When scanning it.
        let publisher = service.loginWithQRCode(data: Self.reciprocateQRCode(serverName: "evil.com"))
        var cancellable: AnyCancellable?
        let error: AuthenticationServiceError? = await withCheckedContinuation { continuation in
            cancellable = publisher.sink { completion in
                if case .failure(let error) = completion {
                    continuation.resume(returning: error)
                } else {
                    continuation.resume(returning: nil)
                }
            } receiveValue: { _ in }
        }
        cancellable?.cancel()
        
        // Then the login is refused once evil.com's homeserver is resolved, before any QR login starts.
        #expect(error == .qrCodeError(.providerNotAllowed(scannedProvider: "evil.com", allowedProviders: ["*.safechat.family"])))
        #expect(clientFactory.makeAuthenticationClientHomeserverAddressSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksReceivedArguments?.homeserverAddress == "evil.com")
        #expect(client.newLoginWithQrCodeHandlerOauthConfigurationCallsCount == 0)
    }
    
    /// An MSC4108 QR code from a device that is signed in to `serverName` ("reciprocate" intent).
    private static func reciprocateQRCode(serverName: String) -> Data {
        func lengthPrefixed(_ string: String) -> Data {
            let bytes = Data(string.utf8)
            return Data([UInt8(bytes.count >> 8), UInt8(bytes.count & 0xFF)]) + bytes
        }
        var data = Data("MATRIX".utf8)
        data.append(contentsOf: [0x02, 0x04]) // version 2, reciprocate
        data.append(Data(repeating: 0x2A, count: 32)) // ephemeral Curve25519 public key
        data.append(lengthPrefixed("https://rendezvous.example/abcdef"))
        data.append(lengthPrefixed(serverName))
        return data
    }
    
    @Test
    mutating func upstreamServersResolveOutsideTheAllowlist() async throws {
        // Given the app locked to *.safechat.family.
        try await setup(allowOtherAccountProviders: false)
        
        // Then matrix.org (which resolves to matrix-client.matrix.org) is refused as well.
        await #expect(throws: AuthenticationServiceError.homeserverNotAllowed) { try await service.configure(for: "matrix.org", flow: .login).get() }
        #expect(client.homeserverLoginDetailsCallsCount == 0)
    }
    
    // MARK: - Helpers
    
    private mutating func setup(serverAddress: String = "matrix.org",
                                classicAppAccounts: [ClassicAppAccount] = [],
                                availableSecrets: ClassicAppAccount.AvailableSecrets = .complete,
                                loginTokenExchanger: LoginTokenExchangerProtocol = LoginTokenExchangerMock(),
                                allowOtherAccountProviders: Bool = true) async throws {
        var configuration: ClientFactoryMock.Configuration = .init()
        // A family homeserver, reached by its client-server URL as a sign-in link names it.
        configuration.homeserverClients["https://smith.safechat.family"] = ClientSDKMock(.init(serverName: "smith.safechat.family",
                                                                                               homeserverURL: "https://smith.safechat.family",
                                                                                               slidingSyncVersion: .native,
                                                                                               oAuthLoginURL: nil,
                                                                                               supportsOAuthCreatePrompt: false,
                                                                                               supportsPasswordLogin: true))
        clientFactory = ClientFactoryMock(configuration)
        homeserverClients = configuration.homeserverClients
        
        client = configuration.homeserverClients[serverAddress]
        encryption = EncryptionSDKMock()
        client.encryptionReturnValue = encryption
        
        userSessionStore = UserSessionStoreMock(.init())
        encryptionKeyProvider = MockEncryptionKeyProvider()
        
        let classicAppManager = ClassicAppManagerMock(.init(accounts: classicAppAccounts,
                                                            availableSecrets: availableSecrets,
                                                            secretsBundle: SecretsBundleWithUserIdSDKMock()))
        
        service = AuthenticationService(userSessionStore: userSessionStore,
                                        encryptionKeyProvider: encryptionKeyProvider,
                                        classicAppManager: classicAppManager,
                                        clientFactory: clientFactory,
                                        loginTokenExchanger: loginTokenExchanger,
                                        appSettings: makeAppSettings(allowOtherAccountProviders: allowOtherAccountProviders),
                                        appHooks: AppHooks())
        
        if let classicAppAccount = service.classicAppAccount {
            await service.setupClassicAppAccountState()
            try #require(classicAppAccount.state.isServerSupported == true)
            try #require(classicAppAccount.state.availableSecrets == availableSecrets)
        }
    }
}

/// Family Chat locks the app to `*.safechat.family`; upstream's tests use arbitrary servers, so they opt out.
@MainActor
private func makeAppSettings(allowOtherAccountProviders: Bool) -> AppSettings {
    let appSettings = AppSettings.volatile()
    appSettings.override(accountProviders: appSettings.accountProviders,
                         allowOtherAccountProviders: allowOtherAccountProviders,
                         hideBrandChrome: false,
                         pushGatewayBaseURL: appSettings.pushGatewayBaseURL,
                         oAuthRedirectURL: appSettings.oAuthRedirectURL,
                         oAuthClientURIPath: appSettings.oAuthClientURIPath,
                         websiteURL: appSettings.websiteURL,
                         logoURL: appSettings.logoURL,
                         copyrightURL: appSettings.copyrightURL,
                         acceptableUseURL: appSettings.acceptableUseURL,
                         privacyURL: appSettings.privacyURL,
                         encryptionURL: appSettings.encryptionURL,
                         deviceVerificationURL: appSettings.deviceVerificationURL,
                         chatBackupDetailsURL: appSettings.chatBackupDetailsURL,
                         identityPinningViolationDetailsURL: appSettings.identityPinningViolationDetailsURL,
                         historySharingDetailsURL: appSettings.historySharingDetailsURL,
                         elementWebHosts: appSettings.elementWebHosts,
                         accountProvisioningHost: appSettings.accountProvisioningHost,
                         bugReportApplicationID: appSettings.bugReportApplicationID,
                         analyticsTermsURL: appSettings.analyticsTermsURL,
                         mapTilerConfiguration: AppSettings.bundledMapTilerConfiguration)
    return appSettings
}

struct MockEncryptionKeyProvider: EncryptionKeyProviderProtocol {
    private let key = "12345678"
    
    func generateKey() -> Data {
        Data(key.utf8)
    }
}
