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
    private let appSettings: AppSettings
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
        self.appSettings = appSettings
        self.userIndicatorController = userIndicatorController
        canReportProblem = isBugReportServiceEnabled
        
        let isQRCodeScanningSupported = !ProcessInfo.processInfo.isiOSAppOnMac
        let isClassicAppAccountAllowed = authenticationService.classicAppAccount.map {
            appSettings.isAllowedHomeserver(serverName: $0.serverName, homeserverURL: $0.homeserverURL.absoluteString)
        } ?? false
        // A single wildcard rule (`*.safechat.family`) is not a server to sign in to: the user types their own.
        let pickableProviders = appSettings.pickableAccountProviders
        let lockedServerName = pickableProviders.count == 1 && !appSettings.hasWildcardAccountProvider ? pickableProviders[0] : nil
        
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
            AuthenticationStartScreenViewState(serverName: lockedServerName,
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
            // A control panel sign-in code is only redeemed once the user confirms the account it signs in to, so a
            // link can't quietly sign them in to someone else's account. The screen underneath is the password fallback.
            confirmSignInCode(provisioningParameters)
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
    
    /// Asks the user to confirm the account a sign-in code signs in to before redeeming it. Cancelling drops the code
    /// and leaves the usual "Sign in to …" button for the password sign-in.
    private func confirmSignInCode(_ provisioningParameters: AccountProvisioningParameters) {
        let title = if let userID = provisioningParameters.loginHintUserID {
            UntranslatedL10n.screenOnboardingSignInCodeConfirmTitle(userID)
        } else {
            UntranslatedL10n.screenOnboardingSignInCodeConfirmTitleNoHint(provisioningParameters.accountProvider)
        }
        state.bindings.alertInfo = AlertInfo(id: .signInCodeConfirmation,
                                             title: title,
                                             message: UntranslatedL10n.screenOnboardingSignInCodeConfirmMessage,
                                             primaryButton: .init(title: L10n.actionCancel, role: .cancel) {
                                                 MXLog.info("Sign-in code declined by the user.")
                                             },
                                             secondaryButton: .init(title: L10n.actionContinue) { [weak self] in
                                                 self?.redeemSignInCode(provisioningParameters)
                                             })
    }
    
    /// Redeems the link's single-use code against `https://<hs>`. On success the flow completes; on any failure the user
    /// is told why and continues with the usual pre-filled password sign-in. The token goes to the authentication service
    /// and nowhere else.
    private func redeemSignInCode(_ provisioningParameters: AccountProvisioningParameters) {
        guard let token = provisioningParameters.token,
              let hs = provisioningParameters.hs,
              let homeserverURL = provisioningParameters.signInCodeHomeserverURL else {
            MXLog.error("Sign-in code refused: the link's homeserver is not usable.")
            displaySignInCodeError(.signInCodeFailed)
            return
        }
        
        // Defence in depth: the flow coordinator already strips codes for hosts outside the account providers.
        guard appSettings.isAllowedHomeserverHost(hs) else {
            MXLog.error("Sign-in code refused: its homeserver is not an allowed account provider.")
            displaySignInCodeError(.signInCodeFailed)
            return
        }
        
        guard !authenticationService.isRedeemingSignInCode else {
            MXLog.warning("A sign-in code is already being redeemed, ignoring this one.")
            return
        }
        
        startLoading(label: UntranslatedL10n.screenOnboardingSignInCodeLoading)
        
        // The service is captured rather than `self`, so the screen isn't kept alive by an in-flight redemption.
        signInCodeTask = Task { [weak self, authenticationService, userIndicatorController, loadingIndicatorID] in
            let result = await authenticationService.loginWithToken(token,
                                                                    homeserverURL: homeserverURL,
                                                                    accountProvider: provisioningParameters.accountProvider,
                                                                    expectedUserID: provisioningParameters.loginHintUserID,
                                                                    initialDeviceName: UIDevice.current.initialDeviceName)
            userIndicatorController.retractIndicatorWithId(loadingIndicatorID)
            guard let self else { return }
            
            switch result {
            case .success(let userSession):
                actionsSubject.send(.signedIn(userSession))
            case .failure(.invalidCredentials):
                displaySignInCodeError(.signInCodeRejected)
            case .failure(.signInCodeAccountMismatch):
                displaySignInCodeError(.signInCodeAccountMismatch)
            case .failure:
                displaySignInCodeError(.signInCodeFailed)
            }
        }
    }
    
    private func displaySignInCodeError(_ alertType: AuthenticationStartScreenAlertType) {
        let message = switch alertType {
        case .signInCodeRejected: UntranslatedL10n.screenOnboardingSignInCodeRejectedMessage
        case .signInCodeAccountMismatch: UntranslatedL10n.screenOnboardingSignInCodeAccountMismatchMessage
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
            // Family Chat: a sign-in link's `hs` is the family's homeserver itself, already checked against the account
            // providers, whereas its `account_provider` may be the family's own domain (`smith.ie`). So the password
            // sign-in (e.g. after a failed code) goes straight to `hs`, with the login hint pre-filling the username.
            let homeserverAddress = provisioningParameters?.signInCodeHomeserverURL?.absoluteString ?? serverName
            await configureAccountProvider(homeserverAddress, loginHint: provisioningParameters?.loginHint)
        } else {
            actionsSubject.send(.login) // No need to configure anything here, continue the flow.
        }
    }
    
    private func configureAccountProvider(_ accountProvider: String, loginHint: String? = nil, fallbackHomeserverURL: URL? = nil) async {
        startLoading()
        defer { stopLoading() }
        
        if case .failure(let error) = await authenticationService.configure(for: accountProvider, flow: .login) {
            // Family Chat: a server that resolves outside the account providers is refused, never retried elsewhere.
            if error == .homeserverNotAllowed {
                displayHomeserverNotAllowed()
                return
            }
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
    
    private func displayHomeserverNotAllowed() {
        state.bindings.alertInfo = AlertInfo(id: .homeserverNotAllowed,
                                             title: L10n.commonServerNotSupported,
                                             message: UntranslatedL10n.screenChangeServerErrorNotFamilyChatServer)
    }
}
