//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias AuthenticationStartScreenViewModelType = StateStoreViewModelV2<AuthenticationStartScreenViewState, AuthenticationStartScreenViewAction>

class AuthenticationStartScreenViewModel: AuthenticationStartScreenViewModelType, AuthenticationStartScreenViewModelProtocol {
    private let authenticationService: AuthenticationServiceProtocol
    private let provisioningParameters: AccountProvisioningParameters?
    private let appMediator: AppMediatorProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    
    private let canReportProblem: Bool
    
    private var actionsSubject: PassthroughSubject<AuthenticationStartScreenViewModelAction, Never> = .init()
    
    var actions: AnyPublisher<AuthenticationStartScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(authenticationService: AuthenticationServiceProtocol,
         provisioningParameters: AccountProvisioningParameters?,
         isBugReportServiceEnabled: Bool,
         appMediator: AppMediatorProtocol,
         appSettings: AppSettings,
         mediaProvider: MediaProviderProtocol?,
         notificationCenter: NotificationCenter = .default,
         userIndicatorController: UserIndicatorControllerProtocol) {
        self.authenticationService = authenticationService
        self.provisioningParameters = provisioningParameters
        self.appMediator = appMediator
        self.userIndicatorController = userIndicatorController
        canReportProblem = isBugReportServiceEnabled
        
        let isQRCodeScanningSupported = !ProcessInfo.processInfo.isiOSAppOnMac
        let classicAppAccountProvider = authenticationService.classicAppAccount?.serverName
        let isClassicAppAccountAllowed = classicAppAccountProvider.map { appSettings.isAllowedAccountProvider($0) } ?? false
        
        let initialViewState = if let provisioningParameters, !appSettings.allowOtherAccountProviders {
            // Family Chat: a provisioning link for an allowed family server behaves as it does upstream, with
            // account creation hidden as for every locked-down configuration.
            AuthenticationStartScreenViewState(serverName: provisioningParameters.accountProvider,
                                               showCreateAccountButton: false,
                                               showQRCodeLoginButton: false,
                                               classicAppMode: nil,
                                               hideBrandChrome: appSettings.hideBrandChrome)
        } else if !appSettings.allowOtherAccountProviders {
            // We don't show the create account button when custom providers are disallowed.
            // The assumption here being that if you're running a custom app, your users will already be created.
            // A single wildcard rule (`*.safechat.family`) is not a server to sign in to: the user types their own.
            let pickableProviders = appSettings.pickableAccountProviders
            AuthenticationStartScreenViewState(serverName: pickableProviders.count == 1 && !appSettings.hasWildcardAccountProvider ? pickableProviders[0] : nil,
                                               showCreateAccountButton: false,
                                               showQRCodeLoginButton: isQRCodeScanningSupported,
                                               classicAppMode: isClassicAppAccountAllowed ? authenticationService.classicAppAccount.map { .welcomeBack($0) } : nil,
                                               hideBrandChrome: appSettings.hideBrandChrome)
        } else if let provisioningParameters {
            // We only show the "Sign in to …" button when using a provisioning link.
            AuthenticationStartScreenViewState(serverName: provisioningParameters.accountProvider,
                                               showCreateAccountButton: false,
                                               showQRCodeLoginButton: false,
                                               classicAppMode: nil,
                                               hideBrandChrome: appSettings.hideBrandChrome)
        } else {
            // The default configuration.
            AuthenticationStartScreenViewState(serverName: nil,
                                               showCreateAccountButton: appSettings.showCreateAccountButton,
                                               showQRCodeLoginButton: isQRCodeScanningSupported,
                                               classicAppMode: authenticationService.classicAppAccount.map { .welcomeBack($0) },
                                               hideBrandChrome: appSettings.hideBrandChrome)
        }
        
        super.init(initialViewState: initialViewState, mediaProvider: mediaProvider)
        
        notificationCenter.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.reloadClassicAppAccount()
            }
            .store(in: &cancellables)
        
        if let provisioningParameters, provisioningParameters.hasSignInCode {
            // A control panel sign-in code is redeemed straight away; the screen underneath is the password fallback.
            signInCodeTask = Task { await self.loginWithSignInCode(provisioningParameters) }
        }
    }
    
    override func process(viewAction: AuthenticationStartScreenViewAction) {
        switch viewAction {
        case .updateWindow(let window):
            guard state.window != window else { return }
            state.window = window
        case .reportProblem:
            if canReportProblem {
                actionsSubject.send(.reportProblem)
            }
        case .developerOptions:
            actionsSubject.send(.developerOptions)
            
        case .loginWithQR:
            actionsSubject.send(.loginWithQR)
        case .login:
            Task { await login() }
        case .register:
            actionsSubject.send(.register)
            
        case .continueWithClassic(let account):
            Task { await login(classicAppAccount: account) }
        case .otherOptions(let account):
            state.classicAppMode = .otherOptions(account)
        case .closeOtherOptions(let account):
            state.classicAppMode = .welcomeBack(account)
        case .openClassicApp:
            guard let classicAppDeepLinkURL = InfoPlistReader.main.classicAppDeepLinkURL else { return }
            appMediator.open(classicAppDeepLinkURL)
        }
    }
    
    // MARK: - Private
    
    @CancellableTask private var signInCodeTask: Task<Void, Never>?
    
    /// Redeems the link's single-use code against `https://<hs>`. On success the flow completes; on any failure the user
    /// is told why and continues with the usual pre-filled password sign-in. The token goes to the authentication service
    /// and nowhere else.
    private func loginWithSignInCode(_ provisioningParameters: AccountProvisioningParameters) async {
        guard let token = provisioningParameters.token,
              let hs = provisioningParameters.hs,
              let homeserverURL = provisioningParameters.signInCodeHomeserverURL else { return }
        
        // Defence in depth: the flow coordinator already strips codes for hosts outside the account providers.
        guard appSettings.isAllowedAccountProvider(hs) else {
            MXLog.error("Sign-in code refused: its homeserver is not an allowed account provider.")
            displaySignInCodeError(.signInCodeFailed)
            return
        }
        
        startLoading(label: UntranslatedL10n.screenOnboardingSignInCodeLoading)
        defer { stopLoading() }
        
        switch await authenticationService.loginWithToken(token, homeserverURL: homeserverURL, initialDeviceName: UIDevice.current.initialDeviceName) {
        case .success(let userSession):
            actionsSubject.send(.signedIn(userSession))
        case .failure(.invalidCredentials):
            displaySignInCodeError(.signInCodeRejected)
        case .failure:
            displaySignInCodeError(.signInCodeFailed)
        }
    }
    
    private func displaySignInCodeError(_ alertType: AuthenticationStartScreenAlertType) {
        let message = switch alertType {
        case .signInCodeRejected: UntranslatedL10n.screenOnboardingSignInCodeRejectedMessage
        default: UntranslatedL10n.screenOnboardingSignInCodeFailedMessage
        }
        state.bindings.alertInfo = AlertInfo(id: alertType,
                                             title: UntranslatedL10n.screenOnboardingSignInCodeRejectedTitle,
                                             message: message,
                                             primaryButton: .init(title: L10n.actionContinue) { [weak self] in
                                                 // Fall through to the password sign-in for the same family server.
                                                 Task { await self?.login() }
                                             })
    }
    
    private func login(classicAppAccount: ClassicAppAccount? = nil) async {
        if let classicAppAccount {
            if classicAppAccount.state.availableSecrets == .requiresBackup {
                state.bindings.showClassicAppBackupInstructions = true
            } else {
                await configureAccountProvider(classicAppAccount.serverName,
                                               loginHint: "mxid:\(classicAppAccount.userID)",
                                               fallbackHomeserverURL: classicAppAccount.homeserverURL)
            }
        } else if let serverName = state.serverName {
            await configureAccountProvider(serverName, loginHint: provisioningParameters?.loginHint)
        } else {
            actionsSubject.send(.login) // No need to configure anything here, continue the flow.
        }
    }
    
    private func configureAccountProvider(_ accountProvider: String, loginHint: String? = nil, fallbackHomeserverURL: URL? = nil) async {
        startLoading()
        defer { stopLoading() }
        
        if case .failure = await authenticationService.configure(for: accountProvider, flow: .login) {
            // Try the fallback URL before showing an error.
            if let fallbackHomeserverURL,
               case .success = await authenticationService.configure(for: fallbackHomeserverURL.absoluteString, flow: .login) {
                // Fallback succeeded, continue with the flow.
            } else {
                // As the server was provisioned, we don't worry about the specifics and show a generic error to the user.
                // Element Classic accounts aren't shown for unsupported servers either, so nothing to do here.
                displayError()
                return
            }
        }
        
        guard authenticationService.homeserver.value.loginMode.supportsOAuthFlow else {
            actionsSubject.send(.loginDirectlyWithPassword(loginHint: loginHint))
            return
        }
        
        guard let window = state.window else {
            displayError()
            return
        }
        
        switch await authenticationService.urlForOAuthLogin(loginHint: loginHint) {
        case .success(let oAuthData):
            actionsSubject.send(.loginDirectlyWithOAuth(data: oAuthData, window: window))
        case .failure:
            displayError()
        }
    }
    
    @CancellableTask private var reloadClassicAppSecretsTask: Task<Void, Never>?
    private func reloadClassicAppAccount() {
        guard case let .welcomeBack(classicAppAccount) = state.classicAppMode else { return }
        
        reloadClassicAppSecretsTask = Task { [weak self] in
            await self?.authenticationService.refreshClassicAppAccountState()
            
            guard !Task.isCancelled else { return }
            
            if let availableSecrets = classicAppAccount.state.availableSecrets, availableSecrets != .requiresBackup {
                await MainActor.run { self?.state.bindings.showClassicAppBackupInstructions = false }
            }
        }
    }
    
    // MARK: - User Indicators
    
    private let loadingIndicatorID = "\(AuthenticationStartScreenViewModel.self)-Loading"
    
    private func startLoading(label: String = L10n.commonLoading) {
        userIndicatorController.submitIndicator(UserIndicator(id: loadingIndicatorID,
                                                              type: .modal,
                                                              title: label,
                                                              persistent: true))
    }
    
    private func stopLoading() {
        userIndicatorController.retractIndicatorWithId(loadingIndicatorID)
    }
    
    private func displayError() {
        state.bindings.alertInfo = AlertInfo(id: .genericError)
    }
}
