//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import MatrixRustSDKMocks
import Testing
import UIKit

@MainActor
final class AuthenticationStartScreenViewModelTests {
    var clientFactory: ClientFactoryMock!
    var client: ClientSDKMock!
    var familyClient: ClientSDKMock!
    var evilClient: ClientSDKMock!
    var classicAppManager: ClassicAppManagerMock?
    var notificationCenter: NotificationCenter!
    var appSettings: AppSettings!
    var authenticationService: AuthenticationServiceProtocol!
    
    var viewModel: AuthenticationStartScreenViewModel!
    var context: AuthenticationStartScreenViewModel.Context {
        viewModel.context
    }
    
    init() {
        appSettings = AppSettings.volatile()
        // Family Chat locks the app to a single account provider. Restore the upstream default
        // here so that each test can opt in to the locked-down configuration explicitly.
        setAccountProviders(["matrix.org"], allowOtherAccountProviders: true)
    }
    
    @Test
    func initialState() async throws {
        // Given a view model that has no provisioning parameters.
        await setupViewModel()
        #expect(authenticationService.homeserver.value.loginMode == .unknown)
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesCallsCount == 0)
        
        // When tapping any of the buttons on the screen
        let actions: [(AuthenticationStartScreenViewAction, AuthenticationStartScreenViewModelAction)] = [
            (.loginWithQR, .loginWithQR),
            (.login, .login),
            (.register, .register),
            (.reportProblem, .reportProblem)
        ]
        
        for action in actions {
            let deferred = deferFulfillment(viewModel.actions) { $0 == action.1 }
            context.send(viewAction: action.0)
            try await deferred.fulfill()
            
            // Then the authentication service should not be used yet.
            #expect(clientFactory.makeAuthenticationClientHomeserverAddressSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksCallsCount == 0)
            #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesCallsCount == 0)
            #expect(authenticationService.homeserver.value.loginMode == .unknown)
        }
    }
    
    @Test
    func provisionedOAuthState() async throws {
        // Given a view model that has been provisioned with a server that supports OAuth.
        await setupViewModel(provisioningParameters: .init(accountProvider: "company.com", loginHint: "user@company.com"))
        #expect(authenticationService.homeserver.value.loginMode == .unknown)
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesCallsCount == 0)
        
        // When tapping the login button the authentication service should be used and the screen
        // should request to continue the flow without any server selection needed.
        let deferred = deferFulfillment(viewModel.actions) { $0.isLoginDirectlyWithOAuth }
        context.send(viewAction: .login)
        try await deferred.fulfill()
        
        #expect(clientFactory.makeAuthenticationClientHomeserverAddressSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksCallsCount == 1)
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesCallsCount == 1)
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesReceivedArguments?.prompt == .consent)
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesReceivedArguments?.loginHint == "user@company.com")
        #expect(authenticationService.homeserver.value.loginMode == .oAuth(supportsCreatePrompt: false))
    }
    
    @Test
    func provisionedPasswordState() async throws {
        // Given a view model that has been provisioned with a server that does not support OAuth.
        await setupViewModel(provisioningParameters: .init(accountProvider: "company.com", loginHint: "user@company.com"), supportsOAuth: false)
        #expect(authenticationService.homeserver.value.loginMode == .unknown)
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesCallsCount == 0)
        
        // When tapping the login button the authentication service should be used and the screen
        // should request to continue the flow without any server selection needed.
        let deferred = deferFulfillment(viewModel.actions) { $0.isLoginDirectlyWithPassword }
        context.send(viewAction: .login)
        try await deferred.fulfill()
        
        // Then a call to configure service should be made.
        #expect(clientFactory.makeAuthenticationClientHomeserverAddressSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksCallsCount == 1)
        #expect(authenticationService.homeserver.value.loginMode == .password)
    }
    
    @Test
    func singleProviderOAuthState() async throws {
        // Given a view model that for an app that only allows the use of a single provider that supports OAuth.
        setAccountProviders(["company.com"])
        await setupViewModel()
        #expect(authenticationService.homeserver.value.loginMode == .unknown)
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesCallsCount == 0)
        
        // When tapping the login button the authentication service should be used and the screen
        // should request to continue the flow without any server selection needed.
        let deferred = deferFulfillment(viewModel.actions) { $0.isLoginDirectlyWithOAuth }
        context.send(viewAction: .login)
        try await deferred.fulfill()
        
        #expect(clientFactory.makeAuthenticationClientHomeserverAddressSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksCallsCount == 1)
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesCallsCount == 1)
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesReceivedArguments?.prompt == .consent)
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesReceivedArguments?.loginHint == nil)
        #expect(authenticationService.homeserver.value.loginMode == .oAuth(supportsCreatePrompt: false))
    }
    
    @Test
    func singleProviderPasswordState() async throws {
        // Given a view model that for an app that only allows the use of a single provider that does not support OAuth.
        setAccountProviders(["company.com"])
        await setupViewModel(supportsOAuth: false)
        #expect(authenticationService.homeserver.value.loginMode == .unknown)
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesCallsCount == 0)
        
        // When tapping the login button the authentication service should be used and the screen
        // should request to continue the flow without any server selection needed.
        let deferred = deferFulfillment(viewModel.actions) { $0.isLoginDirectlyWithPassword }
        context.send(viewAction: .login)
        try await deferred.fulfill()
        
        // Then a call to configure service should be made.
        #expect(clientFactory.makeAuthenticationClientHomeserverAddressSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksCallsCount == 1)
        #expect(authenticationService.homeserver.value.loginMode == .password)
    }
    
    // MARK: - Classic App Account
    
    @Test
    func classicAppAccount() async throws {
        // Given a view model with a Classic app account whose server name resolves successfully.
        let classicAppAccount = makeClassicAppAccount()
        await setupViewModel(classicAppAccount: classicAppAccount)
        guard case .welcomeBack(let account) = context.viewState.classicAppMode else {
            Issue.record("Expected classicAppMode to be .welcomeBack")
            return
        }
        #expect(account == classicAppAccount)
        
        // When continuing with the Classic app account the authentication service should be used and the screen
        // should request to continue the flow without any server selection needed.
        let deferred = deferFulfillment(viewModel.actions) { $0.isLoginDirectlyWithOAuth }
        context.send(viewAction: .continueWithClassic(classicAppAccount))
        try await deferred.fulfill()
        
        #expect(clientFactory.makeAuthenticationClientHomeserverAddressSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksCallsCount == 1)
        #expect(clientFactory.makeAuthenticationClientHomeserverAddressSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksReceivedArguments?.homeserverAddress == "company.com")
        #expect(authenticationService.homeserver.value.loginMode == .oAuth(supportsCreatePrompt: false))
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesReceivedArguments?.loginHint == "mxid:\(classicAppAccount.userID)")
    }
    
    @Test
    func classicAppAccountWithoutWellKnown() async throws {
        // Given a view model where the Classic app account's server name has no well-known file.
        let classicAppAccount = makeClassicAppAccount(serverName: "unknown-server.org",
                                                      homeserverURL: "https://matrix.company.com")
        await setupViewModel(classicAppAccount: classicAppAccount)
        guard case .welcomeBack(let account) = context.viewState.classicAppMode else {
            Issue.record("Expected classicAppMode to be .welcomeBack")
            return
        }
        #expect(account == classicAppAccount)
        
        // When continuing with the Classic app account the authentication service should be used with the direct homeserver URL
        // and the screen should request to continue the flow without any server selection needed.
        let deferred = deferFulfillment(viewModel.actions) { $0.isLoginDirectlyWithOAuth }
        context.send(viewAction: .continueWithClassic(classicAppAccount))
        try await deferred.fulfill()
        
        #expect(clientFactory.makeAuthenticationClientHomeserverAddressSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksCallsCount == 2)
        #expect(clientFactory.makeAuthenticationClientHomeserverAddressSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksReceivedArguments?.homeserverAddress == "https://matrix.company.com")
        #expect(authenticationService.homeserver.value.loginMode == .oAuth(supportsCreatePrompt: false))
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesReceivedArguments?.loginHint == "mxid:\(classicAppAccount.userID)")
    }
    
    @Test
    func classicAppAccountOnUnsupportedServer() async {
        // Given a view model with a Classic app account whose server supports neither OAuth nor password login.
        let classicAppAccount = makeClassicAppAccount()
        await setupViewModel(classicAppAccount: classicAppAccount, supportsOAuth: false, supportsPasswordLogin: false)
        guard case .welcomeBack(let account) = context.viewState.classicAppMode else {
            Issue.record("Expected classicAppMode to be .welcomeBack")
            return
        }
        #expect(account == classicAppAccount)
        
        // Then the Classic app account should indicate that it isn't supported (so the view falls back to the standard content).
        #expect(account.state.isServerSupported == false)
    }
    
    @Test
    func provisionedSignInCodeAsksForConfirmationFirst() async throws {
        // Given a provisioning link carrying a sign-in code.
        let exchanger = LoginTokenExchangerMock(.init(result: .success(.mock(userID: "@ana:company.com"))))
        await setupViewModel(provisioningParameters: .anaSignInCode,
                             supportsOAuth: false,
                             loginTokenExchanger: exchanger)
        
        // Then nothing is redeemed until the user confirms the account the code signs in to.
        #expect(context.alertInfo?.id == .signInCodeConfirmation)
        #expect(context.alertInfo?.title.contains("@ana:company.com") == true)
        #expect(context.alertInfo?.secondaryButton != nil)
        #expect(exchanger.exchangeCallsCount == 0)
        
        // When the user cancels.
        let cancelAction = try #require(context.alertInfo?.primaryButton.action)
        cancelAction()
        try await Task.sleep(for: .milliseconds(50))
        
        // Then the code is never sent anywhere.
        #expect(exchanger.exchangeCallsCount == 0)
        #expect(context.viewState.serverName == "company.com")
    }
    
    @Test
    func provisionedSignInCodeSignsIn() async throws {
        // Given a provisioning link carrying a sign-in code the family homeserver accepts.
        let exchanger = LoginTokenExchangerMock(.init(result: .success(.mock(userID: "@ana:company.com"))))
        await setupViewModel(provisioningParameters: .anaSignInCode,
                             supportsOAuth: false,
                             loginTokenExchanger: exchanger)
        
        // When the user confirms the account.
        let deferred = deferFulfillment(viewModel.actions) { $0.isSignedIn }
        try confirmSignInCode()
        
        // Then the code is redeemed against https://<hs> and the flow completes, no password prompt.
        try await deferred.fulfill()
        #expect(exchanger.exchangeCallsCount == 1)
        #expect(exchanger.exchangeReceivedArguments?.token == "syl_code")
        #expect(exchanger.exchangeReceivedArguments?.homeserverURL == "https://company.com")
        #expect(exchanger.logoutCallsCount == 0)
        #expect(context.viewState.serverName == "company.com")
    }
    
    @Test
    func provisionedSignInCodeRejectedFallsBackToPassword() async throws {
        // Given a provisioning link whose sign-in code was already used.
        let exchanger = LoginTokenExchangerMock(.init(result: .failure(.rejected(errcode: "M_FORBIDDEN"))))
        await setupViewModel(provisioningParameters: .anaSignInCode,
                             supportsOAuth: false,
                             loginTokenExchanger: exchanger)
        
        // When the user confirms the account.
        let deferredAlert = deferFulfillment(context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .signInCodeRejected }
        try confirmSignInCode()
        
        // Then the user is told the code cannot be used.
        try await deferredAlert.fulfill()
        #expect(exchanger.exchangeCallsCount == 1)
        
        // When continuing, the password flow for the same server follows, pre-filled from the link.
        let deferredAction = deferFulfillment(viewModel.actions) { $0 == .loginDirectlyWithPassword(loginHint: "mxid:@ana:company.com") }
        let continueAction = try #require(context.alertInfo?.primaryButton.action)
        continueAction()
        try await deferredAction.fulfill()
        #expect(clientFactory.makeAuthenticationClientHomeserverAddressSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksReceivedArguments?.homeserverAddress == "company.com")
    }
    
    // MARK: - Custom domains (family-chat#254)
    
    @Test
    func customDomainSignInCodeRedeemsAgainstTheHomeserver() async throws {
        // Given the app locked to *.safechat.family and a sign-in link for a family on its own domain.
        setAccountProviders(["*.safechat.family"])
        let exchanger = LoginTokenExchangerMock(.init(result: .success(.mock(userID: "@kid:smith.ie"))))
        await setupViewModel(provisioningParameters: .kidCustomDomainSignInCode,
                             supportsOAuth: false,
                             loginTokenExchanger: exchanger)
        #expect(context.viewState.serverName == "smith.ie")
        #expect(context.alertInfo?.title.contains("@kid:smith.ie") == true)
        
        // When the user confirms the account.
        let deferred = deferFulfillment(viewModel.actions) { $0.isSignedIn }
        try confirmSignInCode()
        
        // Then the code is redeemed against `hs` and the custom-domain account is signed in.
        try await deferred.fulfill()
        #expect(exchanger.exchangeReceivedArguments?.homeserverURL == "https://smith.safechat.family")
        #expect(exchanger.logoutCallsCount == 0)
    }
    
    @Test
    func customDomainSignInCodeForAnotherAccountIsDiscarded() async throws {
        // Given a custom-domain link whose code signs in to another account.
        setAccountProviders(["*.safechat.family"])
        let exchanger = LoginTokenExchangerMock(.init(result: .success(.mock(userID: "@mallory:smith.ie"))))
        await setupViewModel(provisioningParameters: .kidCustomDomainSignInCode,
                             supportsOAuth: false,
                             loginTokenExchanger: exchanger)
        
        let deferredAlert = deferFulfillment(context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .signInCodeAccountMismatch }
        try confirmSignInCode()
        
        // Then it is refused and logged out again.
        try await deferredAlert.fulfill()
        #expect(exchanger.logoutCallsCount == 1)
    }
    
    @Test
    func customDomainRejectedCodeFallsBackToPasswordThroughDiscovery() async throws {
        // Given a custom-domain link whose code was already used.
        setAccountProviders(["*.safechat.family"])
        let exchanger = LoginTokenExchangerMock(.init(result: .failure(.rejected(errcode: "M_FORBIDDEN"))))
        await setupViewModel(provisioningParameters: .kidCustomDomainSignInCode,
                             supportsOAuth: false,
                             loginTokenExchanger: exchanger)
        let deferredAlert = deferFulfillment(context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .signInCodeRejected }
        try confirmSignInCode()
        try await deferredAlert.fulfill()
        
        // When continuing to the password sign-in.
        let deferredAction = deferFulfillment(viewModel.actions) { $0 == .loginDirectlyWithPassword(loginHint: "mxid:@kid:smith.ie") }
        let continueAction = try #require(context.alertInfo?.primaryButton.action)
        continueAction()
        try await deferredAction.fulfill()
        
        // Then it goes to the family's domain through discovery (never straight to the link's `hs`), with the
        // username pre-filled from the hint.
        #expect(clientFactory.makeAuthenticationClientHomeserverAddressSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksReceivedArguments?.homeserverAddress == "smith.ie")
    }
    
    @Test
    func passwordFallbackNeverGoesToTheLinksHomeserver() async throws {
        // Given a crafted link: a family's domain and account, but someone else's (allowlisted) `hs` and a bogus code,
        // with the family's domain resolving elsewhere than that `hs` (here: outside the allowlist altogether).
        setAccountProviders(["*.safechat.family"])
        let exchanger = LoginTokenExchangerMock(.init(result: .failure(.rejected(errcode: "M_FORBIDDEN"))))
        await setupViewModel(provisioningParameters: .init(accountProvider: "evil.com",
                                                           loginHint: "mxid:@kid:evil.com",
                                                           hs: "smith.safechat.family",
                                                           token: "syl_bogus"),
                             supportsOAuth: false,
                             loginTokenExchanger: exchanger)
        let deferredRejection = deferFulfillment(context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .signInCodeRejected }
        try confirmSignInCode()
        try await deferredRejection.fulfill()
        
        // When continuing to the password sign-in.
        let deferredAlert = deferFulfillment(context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .homeserverNotAllowed }
        let continueAction = try #require(context.alertInfo?.primaryButton.action)
        continueAction()
        try await deferredAlert.fulfill()
        
        // Then the password form is never shown: discovery refused the domain and nothing fell back to `hs`.
        let addresses = clientFactory.makeAuthenticationClientHomeserverAddressSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksReceivedInvocations.map { $0.homeserverAddress }
        #expect(addresses == ["https://smith.safechat.family", "evil.com"])
        #expect(familyClient.loginUsernamePasswordInitialDeviceNameDeviceIdCallsCount == 0)
    }
    
    @Test
    func customDomainLinkWithoutCodeIsJudgedByWhereItResolves() async throws {
        // Given the app locked to *.safechat.family and a link for `smith.ie`, which delegates to smith.safechat.family.
        setAccountProviders(["*.safechat.family"])
        await setupViewModel(provisioningParameters: .init(accountProvider: "smith.ie", loginHint: "mxid:@kid:smith.ie"),
                             supportsOAuth: false)
        
        // When tapping "Sign in to smith.ie".
        let deferred = deferFulfillment(viewModel.actions) { $0 == .loginDirectlyWithPassword(loginHint: "mxid:@kid:smith.ie") }
        context.send(viewAction: .login)
        
        // Then the password sign-in for that domain follows.
        try await deferred.fulfill()
        #expect(clientFactory.makeAuthenticationClientHomeserverAddressSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksReceivedArguments?.homeserverAddress == "smith.ie")
    }
    
    @Test
    func linkForADomainResolvingElsewhereIsRefused() async throws {
        // Given the app locked to *.safechat.family and a link for `evil.com`, which resolves to https://evil.com.
        setAccountProviders(["*.safechat.family"])
        await setupViewModel(provisioningParameters: .init(accountProvider: "evil.com", loginHint: "mxid:@kid:evil.com"),
                             supportsOAuth: false)
        
        // When tapping "Sign in to evil.com".
        let deferred = deferFulfillment(context.observe(\.viewState.bindings.alertInfo)) { $0 != nil }
        context.send(viewAction: .login)
        try await deferred.fulfill()
        
        // Then the user is told it isn't a Family Chat server and nothing but discovery went there.
        #expect(context.alertInfo?.id == .homeserverNotAllowed)
        #expect(context.alertInfo?.message == UntranslatedL10n.screenChangeServerErrorNotFamilyChatServer)
        #expect(evilClient.homeserverLoginDetailsCallsCount == 0)
        #expect(evilClient.loginUsernamePasswordInitialDeviceNameDeviceIdCallsCount == 0)
    }
    
    @Test
    func provisionedSignInCodeForAnotherAccountIsDiscarded() async throws {
        // Given a sign-in code that the homeserver redeems for another account than the link named (login CSRF).
        let exchanger = LoginTokenExchangerMock(.init(result: .success(.mock(userID: "@mallory:company.com"))))
        await setupViewModel(provisioningParameters: .anaSignInCode,
                             supportsOAuth: false,
                             loginTokenExchanger: exchanger)
        
        // When the user confirms signing in as Ana.
        let deferredAlert = deferFulfillment(context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .signInCodeAccountMismatch }
        try confirmSignInCode()
        
        // Then the user is not signed in and the unexpected session is logged out again.
        try await deferredAlert.fulfill()
        #expect(exchanger.exchangeCallsCount == 1)
        #expect(exchanger.logoutCallsCount == 1)
        #expect(exchanger.logoutReceivedArguments?.accessToken == "syt_access")
    }
    
    @Test
    func provisionedSignInCodeForDisallowedHomeserverIsNeverSent() async throws {
        // Given the app is locked to *.safechat.family and a link names another homeserver for its code.
        setAccountProviders(["*.safechat.family", "company.com"])
        let exchanger = LoginTokenExchangerMock(.init(result: .success(.mockAna)))
        await setupViewModel(provisioningParameters: .init(accountProvider: "company.com", loginHint: nil, hs: "evil.example", token: "syl_code"),
                             supportsOAuth: false,
                             loginTokenExchanger: exchanger)
        #expect(context.alertInfo?.title.contains("company.com") == true)
        
        // When the user confirms.
        let deferredAlert = deferFulfillment(context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .signInCodeFailed }
        try confirmSignInCode()
        
        // Then the code is refused locally and nothing is sent.
        try await deferredAlert.fulfill()
        #expect(exchanger.exchangeCallsCount == 0)
    }
    
    @Test
    func classicAppAccountWithProvisioningLink() async {
        // Given a view model that has been provisioned with a provisioning link (and a classic account exists).
        let classicAppAccount = makeClassicAppAccount()
        await setupViewModel(classicAppAccount: classicAppAccount,
                             provisioningParameters: .init(accountProvider: "company.com", loginHint: nil))
        
        // Then the Classic app account should not be shown — provisioning takes precedence.
        #expect(context.viewState.classicAppMode == nil)
    }
    
    @Test
    func singleProviderWithMatchingClassicAppAccount() async {
        // Given a view model for an app that only allows a single provider that matches the Classic account's server.
        let classicAppAccount = makeClassicAppAccount(serverName: "company.com",
                                                      homeserverURL: "https://matrix.company.com")
        setAccountProviders(["company.com"])
        await setupViewModel(classicAppAccount: classicAppAccount)
        
        // Then the Classic app account should be shown as a welcome-back option.
        guard case .welcomeBack(let account) = context.viewState.classicAppMode else {
            Issue.record("Expected classicAppMode to be .welcomeBack")
            return
        }
        #expect(account == classicAppAccount)
    }
    
    @Test
    func singleProviderWithDisallowedClassicAppAccount() async {
        // Given a view model for an app that only allows a single provider that does NOT match the Classic account's server.
        let classicAppAccount = makeClassicAppAccount(serverName: "other-server.org",
                                                      homeserverURL: "https://matrix.other-server.org")
        setAccountProviders(["company.com"])
        await setupViewModel(classicAppAccount: classicAppAccount)
        
        // Then the Classic app account should not be shown since the server is not in the allowed providers.
        #expect(context.viewState.classicAppMode == nil)
    }
    
    @Test
    func classicAppAccountRequiresBackup() async throws {
        // Given a view model with a Classic app account that requires backup before signing in.
        let classicAppAccount = makeClassicAppAccount()
        await setupViewModel(classicAppAccount: classicAppAccount, availableSecrets: .requiresBackup)
        guard case .welcomeBack(let account) = context.viewState.classicAppMode else {
            Issue.record("Expected classicAppMode to be .welcomeBack")
            return
        }
        #expect(account.state.availableSecrets == .requiresBackup)
        
        // When continuing with the Classic account while backup is required.
        var deferred = deferFulfillment(context.observe(\.viewState.bindings.showClassicAppBackupInstructions)) { $0 }
        context.send(viewAction: .continueWithClassic(classicAppAccount))
        
        // Then the backup instructions should be shown.
        try await deferred.fulfill()
        
        // When the user completes the backup in the Classic app and the app returns to the foreground.
        classicAppManager?.availableSecretsForReturnValue = .complete
        deferred = deferFulfillment(context.observe(\.viewState.bindings.showClassicAppBackupInstructions)) { !$0 }
        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        
        // Then the backup instructions sheet should be dismissed.
        try await deferred.fulfill()
        
        // When the user continues with the Classic account again.
        let deferredAction = deferFulfillment(viewModel.actions) { $0.isLoginDirectlyWithOAuth }
        context.send(viewAction: .continueWithClassic(classicAppAccount))
        
        // Then the flow should continue the login process.
        try await deferredAction.fulfill()
    }
    
    // MARK: - Helpers
    
    private func setupViewModel(classicAppAccount: ClassicAppAccount? = nil,
                                provisioningParameters: AccountProvisioningParameters? = nil,
                                supportsOAuth: Bool = true,
                                supportsPasswordLogin: Bool = true,
                                availableSecrets: ClassicAppAccount.AvailableSecrets = .complete,
                                loginTokenExchanger: LoginTokenExchangerProtocol = LoginTokenExchangerMock()) async {
        // Manually create a configuration as the default homeserver address setting is immutable.
        client = ClientSDKMock(.init(oAuthLoginURL: supportsOAuth ? "https://account.company.com/authorize" : nil,
                                     supportsOAuthCreatePrompt: false,
                                     supportsPasswordLogin: supportsPasswordLogin))
        // Map both the server name and the homeserver URL so fallback lookups work.
        // Family Chat: a family on its own domain (`smith.ie` → smith.safechat.family), and a domain resolving elsewhere.
        familyClient = ClientSDKMock(.init(serverName: "smith.ie",
                                           homeserverURL: "https://smith.safechat.family",
                                           oAuthLoginURL: nil,
                                           supportsOAuthCreatePrompt: false,
                                           supportsPasswordLogin: true))
        evilClient = ClientSDKMock(.init(serverName: "evil.com",
                                         homeserverURL: "https://evil.com",
                                         oAuthLoginURL: nil,
                                         supportsOAuthCreatePrompt: false,
                                         supportsPasswordLogin: true))
        let homeserverClients: [String: ClientSDKMock] = ["company.com": client,
                                                          "https://matrix.company.com": client,
                                                          "https://company.com": client, // as a sign-in link names it
                                                          "smith.ie": familyClient,
                                                          "https://smith.safechat.family": familyClient,
                                                          "evil.com": evilClient]
        let configuration = ClientFactoryMock.Configuration(homeserverClients: homeserverClients)
        
        if let classicAppAccount {
            classicAppManager = ClassicAppManagerMock(.init(accounts: [classicAppAccount], availableSecrets: availableSecrets))
        } else {
            classicAppManager = nil
        }
        
        notificationCenter = NotificationCenter()
        
        clientFactory = ClientFactoryMock(configuration)
        authenticationService = AuthenticationService(userSessionStore: UserSessionStoreMock(.init()),
                                                      encryptionKeyProvider: EncryptionKeyProvider(),
                                                      classicAppManager: classicAppManager,
                                                      clientFactory: clientFactory,
                                                      loginTokenExchanger: loginTokenExchanger,
                                                      appSettings: appSettings,
                                                      appHooks: AppHooks())
        
        await authenticationService.setupClassicAppAccountState()
        
        viewModel = AuthenticationStartScreenViewModel(authenticationService: authenticationService,
                                                       provisioningParameters: provisioningParameters,
                                                       isBugReportServiceEnabled: true,
                                                       appMediator: AppMediatorMock(),
                                                       appSettings: appSettings,
                                                       mediaProvider: MediaProviderMock(.init()),
                                                       notificationCenter: notificationCenter,
                                                       userIndicatorController: UserIndicatorControllerMock())
        
        // Add a fake window in order for the OAuth flow to continue
        viewModel.context.send(viewAction: .updateWindow(UIWindow()))
    }
    
    /// Taps Continue on the sign-in code confirmation.
    private func confirmSignInCode() throws {
        #expect(context.alertInfo?.id == .signInCodeConfirmation)
        let confirmAction = try #require(context.alertInfo?.secondaryButton?.action)
        confirmAction()
    }
    
    private func makeClassicAppAccount(serverName: String = "company.com",
                                       homeserverURL: URL = "https://matrix.company.com") -> ClassicAppAccount {
        ClassicAppAccount(userID: "@user:\(serverName)",
                          displayName: "Classic User",
                          avatarURL: nil,
                          serverName: serverName,
                          homeserverURL: homeserverURL,
                          cryptoStoreURL: "file:///tmp/crypto-store",
                          cryptoStorePassphrase: "passphrase",
                          accessToken: "accessToken")
    }
    
    private func setAccountProviders(_ providers: [String], allowOtherAccountProviders: Bool = false) {
        appSettings.override(accountProviders: providers,
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
    }
}

extension AuthenticationStartScreenViewModelAction {
    var isSignedIn: Bool {
        if case .signedIn = self {
            return true
        }
        return false
    }
    
    var isLoginDirectlyWithOAuth: Bool {
        switch self {
        case .loginDirectlyWithOAuth: true
        default: false
        }
    }
    
    var isLoginDirectlyWithPassword: Bool {
        switch self {
        case .loginDirectlyWithPassword: true
        default: false
        }
    }
}

private extension AccountProvisioningParameters {
    static var anaSignInCode: AccountProvisioningParameters {
        .init(accountProvider: "company.com", loginHint: "mxid:@ana:company.com", hs: "company.com", token: "syl_code")
    }
    
    /// A family on its own domain: Matrix server name `smith.ie`, homeserver `smith.safechat.family`.
    static var kidCustomDomainSignInCode: AccountProvisioningParameters {
        .init(accountProvider: "smith.ie", loginHint: "mxid:@kid:smith.ie", hs: "smith.safechat.family", token: "syl_code")
    }
}
