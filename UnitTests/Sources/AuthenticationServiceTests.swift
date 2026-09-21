//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

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
        #expect(service.homeserver.value == .init(address: "safechat.family", loginMode: .unknown))
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
        let result = await service.loginWithToken("syl_code", homeserverURL: "https://smith.safechat.family", initialDeviceName: "Family Chat iOS")
        
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
        let result = await service.loginWithToken("syl_code", homeserverURL: "https://smith.safechat.family", initialDeviceName: nil)
        
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
        
        let result = await service.loginWithToken("syl_code", homeserverURL: "https://smith.safechat.family", initialDeviceName: nil)
        
        try await #require(throws: AuthenticationServiceError.failedLoggingIn) { try result.get() }
        #expect(userSessionStore.userSessionForSessionDirectoriesPassphraseCallsCount == 0)
    }
    
    // MARK: - Helpers
    
    private mutating func setup(serverAddress: String = "matrix.org",
                                classicAppAccounts: [ClassicAppAccount] = [],
                                availableSecrets: ClassicAppAccount.AvailableSecrets = .complete,
                                loginTokenExchanger: LoginTokenExchangerProtocol = LoginTokenExchangerMock()) async throws {
        var configuration: ClientFactoryMock.Configuration = .init()
        // A family homeserver, reached by its client-server URL as a sign-in link names it.
        configuration.homeserverClients["https://smith.safechat.family"] = ClientSDKMock(.init(serverName: "smith.safechat.family",
                                                                                               homeserverURL: "https://smith.safechat.family",
                                                                                               slidingSyncVersion: .native,
                                                                                               oAuthLoginURL: nil,
                                                                                               supportsOAuthCreatePrompt: false,
                                                                                               supportsPasswordLogin: true))
        let clientFactory = ClientFactoryMock(configuration)
        
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
                                        appSettings: .volatile(),
                                        appHooks: AppHooks())
        
        if let classicAppAccount = service.classicAppAccount {
            await service.setupClassicAppAccountState()
            try #require(classicAppAccount.state.isServerSupported == true)
            try #require(classicAppAccount.state.availableSecrets == availableSecrets)
        }
    }
}

struct MockEncryptionKeyProvider: EncryptionKeyProviderProtocol {
    private let key = "12345678"
    
    func generateKey() -> Data {
        Data(key.utf8)
    }
}
