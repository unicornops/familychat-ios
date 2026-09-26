//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

enum AuthenticationStartScreenViewModelAction {
    case loginWithQR
    case login
    case register
    
    case loginDirectlyWithOAuth(data: OAuthAuthorizationDataProxy, window: UIWindow)
    case loginDirectlyWithPassword(loginHint: String?)
    /// Family Chat: the sign-in code from the provisioning link was redeemed, the user is signed in.
    case signedIn(UserSessionProtocol)
    
    case reportProblem
    case developerOptions
}

extension AuthenticationStartScreenViewModelAction: Equatable {
    static func == (lhs: AuthenticationStartScreenViewModelAction, rhs: AuthenticationStartScreenViewModelAction) -> Bool {
        switch (lhs, rhs) {
        case (.loginWithQR, .loginWithQR), (.login, .login), (.register, .register),
             (.reportProblem, .reportProblem), (.developerOptions, .developerOptions):
            true
        case (.loginDirectlyWithOAuth(let lhsData, let lhsWindow), .loginDirectlyWithOAuth(let rhsData, let rhsWindow)):
            lhsData == rhsData && lhsWindow == rhsWindow
        case (.loginDirectlyWithPassword(let lhsHint), .loginDirectlyWithPassword(let rhsHint)):
            lhsHint == rhsHint
        case (.signedIn(let lhsSession), .signedIn(let rhsSession)):
            lhsSession.clientProxy.userID == rhsSession.clientProxy.userID
        default:
            false
        }
    }
}

struct AuthenticationStartScreenViewState: BindableState {
    /// The presentation anchor used for OAuth authentication.
    var window: UIWindow?
    
    let serverName: String?
    let showCreateAccountButton: Bool
    let showQRCodeLoginButton: Bool
    
    enum ClassicAppMode { case welcomeBack(ClassicAppAccount), otherOptions(ClassicAppAccount) }
    var classicAppMode: ClassicAppMode?
    
    let hideBrandChrome: Bool
    
    var bindings = AuthenticationStartScreenViewStateBindings()
    
    var loginButtonTitle: String {
        if let serverName {
            L10n.screenOnboardingSignInTo(serverName)
        } else if showQRCodeLoginButton {
            L10n.screenOnboardingSignInManually
        } else {
            L10n.actionContinue
        }
    }
}

struct AuthenticationStartScreenViewStateBindings {
    var alertInfo: AlertInfo<AuthenticationStartScreenAlertType>?
    var showClassicAppBackupInstructions = false
}

enum AuthenticationStartScreenAlertType {
    case genericError
    /// The server resolves to a homeserver outside the account providers (a domain that isn't a Family Chat family's).
    case homeserverNotAllowed
    /// Asks the user to confirm the account a sign-in code signs in to before redeeming it.
    case signInCodeConfirmation
    /// The sign-in code signed in to another account than the link named; that session was discarded.
    case signInCodeAccountMismatch
    /// The sign-in code was used already or has expired.
    case signInCodeRejected
    /// The sign-in code could not be redeemed for another reason (server unreachable, unexpected answer).
    case signInCodeFailed
}

enum AuthenticationStartScreenViewAction {
    /// Updates the window used as the OAuth presentation anchor.
    case updateWindow(UIWindow)
    case developerOptions
    case reportProblem
    
    case loginWithQR
    case login
    case register
    
    case continueWithClassic(ClassicAppAccount)
    case otherOptions(ClassicAppAccount)
    case closeOtherOptions(ClassicAppAccount)
    case openClassicApp
}
