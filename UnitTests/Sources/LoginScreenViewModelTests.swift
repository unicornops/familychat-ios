//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Testing

@MainActor
struct LoginScreenViewModelTests {
    var viewModel: LoginScreenViewModelProtocol!
    var context: LoginScreenViewModelType.Context {
        viewModel.context
    }
    
    var clientFactory: ClientFactoryMock!
    var factoryConfiguration: ClientFactoryMock.Configuration!
    var service: AuthenticationServiceProtocol!
    
    @Test
    mutating func basicServer() async {
        // Given the view model configured for a basic server example.com that only supports password authentication.
        await setupViewModel()
        
        // Then the view state should be updated with the homeserver and show the login form.
        #expect(context.viewState.homeserver == .mockBasicServer,
                "The homeserver data should should match the new homeserver.")
        #expect(context.viewState.loginMode == .password,
                "The login form should be shown.")
    }
    
    @Test
    mutating func usernameWithEmptyPassword() async {
        // Given a form with an empty username and password.
        await setupViewModel()
        #expect(context.password.isEmpty,
                "The initial value for the password should be empty.")
        #expect(context.username.isEmpty,
                "The initial value for the username should be empty.")
        #expect(!context.viewState.hasValidCredentials,
                "The credentials should be invalid.")
        #expect(!context.viewState.canSubmit,
                "The form should be blocked for submission.")
        
        // When entering a username without a password.
        context.username = "bob"
        context.password = ""
        
        // Then the credentials should be considered invalid.
        #expect(!context.viewState.hasValidCredentials,
                "The credentials should be invalid.")
        #expect(!context.viewState.canSubmit,
                "The form should be blocked for submission.")
    }
    
    @Test
    mutating func emptyUsernameWithPassword() async {
        // Given a form with an empty username and password.
        await setupViewModel()
        #expect(context.password.isEmpty,
                "The initial value for the password should be empty.")
        #expect(context.username.isEmpty,
                "The initial value for the username should be empty.")
        #expect(!context.viewState.hasValidCredentials,
                "The credentials should be invalid.")
        #expect(!context.viewState.canSubmit,
                "The form should be blocked for submission.")
        
        // When entering a password without a username.
        context.username = ""
        context.password = "12345678"
        
        // Then the credentials should be considered invalid.
        #expect(!context.viewState.hasValidCredentials,
                "The credentials should be invalid.")
        #expect(!context.viewState.canSubmit,
                "The form should be blocked for submission.")
    }
    
    @Test
    mutating func validCredentials() async {
        // Given a form with an empty username and password.
        await setupViewModel()
        #expect(context.password.isEmpty,
                "The initial value for the password should be empty.")
        #expect(context.username.isEmpty,
                "The initial value for the username should be empty.")
        #expect(!context.viewState.hasValidCredentials,
                "The credentials should be invalid.")
        #expect(!context.viewState.canSubmit,
                "The form should be blocked for submission.")
        
        // When entering a username and an 8-character password.
        context.username = "bob"
        context.password = "12345678"
        
        // Then the credentials should be considered valid.
        #expect(context.viewState.hasValidCredentials,
                "The credentials should be valid when the username and password are valid.")
        #expect(context.viewState.canSubmit,
                "The form should be ready to submit.")
    }
    
    @Test
    mutating func loadingServerWithoutPassword() async throws {
        // Given a form with valid credentials.
        await setupViewModel()
        context.username = "@bob:example.com"
        #expect(!context.viewState.hasValidCredentials,
                "The credentials should be not be valid without a password.")
        #expect(!context.viewState.isLoading,
                "The view shouldn't start in a loading state.")
        #expect(!context.viewState.canSubmit,
                "The form should not be submittable.")
        
        // When updating the view model whilst loading a homeserver.
        let deferred = deferFulfillment(context.observe(\.viewState.isLoading),
                                        transitionValues: [true, false])
        context.send(viewAction: .parseUsername)
        
        // Then the view state should represent the loading but never allow submitting to occur.
        try await deferred.fulfill()
        #expect(!context.viewState.isLoading,
                "The view should be back in a loaded state.")
        #expect(!context.viewState.canSubmit,
                "The form should still not be submittable.")
    }
    
    @Test
    mutating func loadingServerWithPasswordEntered() async throws {
        // Given a form with valid credentials.
        await setupViewModel()
        context.username = "@bob:example.com"
        context.password = "12345678"
        #expect(context.viewState.hasValidCredentials,
                "The credentials should be valid.")
        #expect(!context.viewState.isLoading,
                "The view shouldn't start in a loading state.")
        #expect(context.viewState.canSubmit,
                "The form should be ready to submit.")
        
        // When updating the view model whilst loading a homeserver.
        let deferred = deferFulfillment(context.observe(\.viewState.canSubmit),
                                        transitionValues: [false, true])
        context.send(viewAction: .parseUsername)
        
        // Then the view should be blocked from submitting while loading and then become unblocked again.
        try await deferred.fulfill()
        #expect(!context.viewState.isLoading,
                "The view should be back in a loaded state.")
        #expect(context.viewState.canSubmit,
                "The form should be ready to submit.")
    }
    
    @Test
    mutating func oAuthServer() async throws {
        // Given the screen configured for matrix.org
        await setupViewModel()
        
        // When entering a username for a user on a homeserver with OAuth.
        let deferred = deferFulfillment(viewModel.actions) {
            $0.isConfiguredForOAuth
        }
        context.username = "@bob:company.com"
        context.send(viewAction: .parseUsername)
        try await deferred.fulfill()
        
        // Then the view state should be updated with the homeserver and show the OAuth button.
        #expect(context.viewState.loginMode.supportsOAuthFlow,
                "The OAuth button should be shown.")
    }
    
    @Test
    mutating func unsupportedServer() async throws {
        // Given the screen configured for matrix.org
        await setupViewModel()
        #expect(context.alertInfo == nil,
                "There shouldn't be an alert when the screen loads.")
        
        // When entering a username for an unsupported homeserver.
        let deferred = deferFulfillment(context.observe(\.viewState.bindings.alertInfo)) {
            $0 != nil
        }
        context.username = "@bob:server.net"
        context.send(viewAction: .parseUsername)
        try await deferred.fulfill()
        
        // Then the view state should be updated to show an alert.
        #expect(context.alertInfo?.id == .unknown,
                "An alert should be shown to the user.")
    }
    
    @Test
    mutating func elementProRequired() async throws {
        // Given the screen configured for matrix.org
        await setupViewModel()
        #expect(context.alertInfo == nil,
                "There shouldn't be an alert when the screen loads.")
        
        // When entering a username for an unsupported homeserver.
        let deferred = deferFulfillment(context.observe(\.viewState.bindings.alertInfo)) {
            $0 != nil
        }
        context.username = "@bob:secure.gov"
        context.send(viewAction: .parseUsername)
        try await deferred.fulfill()
        
        // Then the view state should be updated to show an alert.
        #expect(context.alertInfo?.id == .elementProAlert,
                "An alert should be shown to the user.")
    }
    
    @Test
    mutating func loginHint() async {
        await setupViewModel(loginHint: "")
        #expect(context.username == "")
        
        await setupViewModel(loginHint: "alice")
        #expect(context.username == "alice")
        
        await setupViewModel(loginHint: "mxid:@alice:example.com")
        #expect(context.username == "@alice:example.com")
    }
    
    @Test
    mutating func matrixIDOnDisallowedServerIsRefused() async throws {
        // Given the app locked to *.safechat.family (the default).
        await setupViewModel(homeserverAddress: "smith.safechat.family", allowOtherAccountProviders: false)
        let matrixDotOrg = try #require(factoryConfiguration.homeserverClients["matrix.org"])
        
        // When entering a Matrix ID on a server that doesn't resolve to a family server.
        let deferred = deferFulfillment(context.observe(\.viewState.bindings.alertInfo)) { $0 != nil }
        context.username = "@bob:matrix.org"
        context.send(viewAction: .parseUsername)
        try await deferred.fulfill()
        
        // Then the sign-in is not moved to that server: only discovery happened, the homeserver was never asked
        // anything and the family server stays configured.
        #expect(context.alertInfo?.id == .accountProviderNotAllowed)
        #expect(context.alertInfo?.message == UntranslatedL10n.screenChangeServerErrorNotFamilyChatServer)
        #expect(matrixDotOrg.homeserverLoginDetailsCallsCount == 0)
        #expect(service.homeserver.value.address == "smith.safechat.family")
        // And the refused Matrix ID is cleared, so its password can't go to the family server instead.
        #expect(context.username == "")
        #expect(!context.viewState.isLoading)
    }
    
    @Test
    mutating func matrixIDOnACustomDomainIsAccepted() async throws {
        // Given the app locked to *.safechat.family, and `smith.ie` delegating to smith.safechat.family.
        await setupViewModel(homeserverAddress: "smith.safechat.family", allowOtherAccountProviders: false)
        let smithDotIE = try #require(factoryConfiguration.homeserverClients["smith.ie"])
        
        // When entering a Matrix ID on the family's own domain.
        let deferred = deferFulfillment(context.observe(\.viewState.homeserver)) { $0.address == "smith.ie" }
        context.username = "@kid:smith.ie"
        context.send(viewAction: .parseUsername)
        try await deferred.fulfill()
        
        // Then the sign-in moves to that domain and the password goes to the homeserver it resolved to.
        #expect(context.alertInfo == nil)
        #expect(context.viewState.loginMode == .password)
        context.password = "12345678"
        let deferredSignIn = deferFulfillment(viewModel.actions) { !$0.isConfiguredForOAuth } // i.e. signed in
        context.send(viewAction: .next)
        try await deferredSignIn.fulfill()
        #expect(smithDotIE.loginUsernamePasswordInitialDeviceNameDeviceIdReceivedArguments?.username == "@kid:smith.ie")
    }
    
    @Test
    mutating func matrixIDOnADomainResolvingElsewhereSendsNoPassword() async throws {
        // Given the app locked to *.safechat.family, and `evil.com` resolving to https://evil.com.
        await setupViewModel(homeserverAddress: "smith.safechat.family", allowOtherAccountProviders: false)
        let evil = try #require(factoryConfiguration.homeserverClients["evil.com"])
        
        // When entering a Matrix ID on it.
        let deferred = deferFulfillment(context.observe(\.viewState.bindings.alertInfo)) { $0 != nil }
        context.username = "@kid:evil.com"
        context.send(viewAction: .parseUsername)
        try await deferred.fulfill()
        
        // Then it is refused with an explanation before any login request.
        #expect(context.alertInfo?.message == UntranslatedL10n.screenChangeServerErrorNotFamilyChatServer)
        #expect(evil.homeserverLoginDetailsCallsCount == 0)
        #expect(evil.loginUsernamePasswordInitialDeviceNameDeviceIdCallsCount == 0)
        #expect(context.username == "")
    }
    
    @Test
    mutating func matrixIDParserDifferentialsAreRefusedBeforeDiscovery() async throws {
        // Given the app locked to *.safechat.family.
        await setupViewModel(homeserverAddress: "smith.safechat.family", allowOtherAccountProviders: false)
        
        for username in ["@kid:evil.com\\.safechat.family", "@kid:evil.com\\@a.safechat.family", "@kid:user@smith.safechat.family"] {
            let callsBefore = clientFactory.makeAuthenticationClientHomeserverAddressSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksCallsCount
            context.alertInfo = nil
            context.username = username
            context.send(viewAction: .parseUsername)
            try await Task.sleep(for: .milliseconds(50))
            
            // Then the SDK never sees the server name.
            #expect(clientFactory.makeAuthenticationClientHomeserverAddressSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksCallsCount == callsBefore,
                    Comment(rawValue: username))
            #expect(service.homeserver.value.address == "smith.safechat.family", Comment(rawValue: username))
        }
    }
    
    // MARK: - Helpers
    
    private mutating func setupViewModel(homeserverAddress: String = "example.com",
                                         loginHint: String? = nil,
                                         allowOtherAccountProviders: Bool = true) async {
        let appSettings = AppSettings.volatile()
        // Family Chat locks the app to `*.safechat.family`; upstream's tests use arbitrary servers, so each test
        // opts in to the locked-down configuration explicitly.
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
        
        factoryConfiguration = ClientFactoryMock.Configuration()
        clientFactory = ClientFactoryMock(factoryConfiguration)
        service = AuthenticationService(userSessionStore: UserSessionStoreMock(.init()),
                                        encryptionKeyProvider: EncryptionKeyProvider(),
                                        classicAppManager: nil,
                                        clientFactory: clientFactory,
                                        appSettings: appSettings,
                                        appHooks: AppHooks())
        
        guard case .success = await service
            .configure(for: homeserverAddress, flow: .login) else {
            Issue.record("A valid server should be configured for the test.")
            return
        }
        
        viewModel = LoginScreenViewModel(authenticationService: service,
                                         loginHint: loginHint,
                                         userIndicatorController: UserIndicatorControllerMock(),
                                         appSettings: appSettings)
    }
}
