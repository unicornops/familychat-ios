// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
internal nonisolated enum UntranslatedL10n {
  /// Source code
  internal static var screenAboutSourceCode: String { return UntranslatedL10n.tr("Untranslated", "screen_about_source_code") }
  /// Family Chat is a fork of Element X by Element (AGPL-3.0); source at https://github.com/unicornops/familychat-ios
  internal static var screenAboutSourceCodeNotice: String { return UntranslatedL10n.tr("Untranslated", "screen_about_source_code_notice") }
  /// You can only sign in to your family's own server, for example %1$@.
  internal static func screenChangeServerErrorNotAllowed(_ p1: Any) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_change_server_error_not_allowed", String(describing: p1))
  }
  /// Search
  internal static var screenHomeTabSearch: String { return UntranslatedL10n.tr("Untranslated", "screen_home_tab_search") }
  /// That sign-in code is for a different account than the one the link named, so you have not been signed in. Ask a parent for a new code, or sign in with your password.
  internal static var screenOnboardingSignInCodeAccountMismatchMessage: String { return UntranslatedL10n.tr("Untranslated", "screen_onboarding_sign_in_code_account_mismatch_message") }
  /// To use this sign-in code for another account, sign out first and then open the code again.
  internal static var screenOnboardingSignInCodeAlreadySignedInMessage: String { return UntranslatedL10n.tr("Untranslated", "screen_onboarding_sign_in_code_already_signed_in_message") }
  /// Only continue if this is your account and you asked a parent for this sign-in code.
  internal static var screenOnboardingSignInCodeConfirmMessage: String { return UntranslatedL10n.tr("Untranslated", "screen_onboarding_sign_in_code_confirm_message") }
  /// Sign in as %1$@?
  internal static func screenOnboardingSignInCodeConfirmTitle(_ p1: Any) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_onboarding_sign_in_code_confirm_title", String(describing: p1))
  }
  /// Sign in to %1$@?
  internal static func screenOnboardingSignInCodeConfirmTitleNoHint(_ p1: Any) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_onboarding_sign_in_code_confirm_title_no_hint", String(describing: p1))
  }
  /// Your family's server could not be reached with this sign-in code. Check your connection and try a new code, or sign in with your password.
  internal static var screenOnboardingSignInCodeFailedMessage: String { return UntranslatedL10n.tr("Untranslated", "screen_onboarding_sign_in_code_failed_message") }
  /// Signing you in…
  internal static var screenOnboardingSignInCodeLoading: String { return UntranslatedL10n.tr("Untranslated", "screen_onboarding_sign_in_code_loading") }
  /// That sign-in code has already been used or has expired. Ask a parent for a new code from the control panel, or sign in with your password.
  internal static var screenOnboardingSignInCodeRejectedMessage: String { return UntranslatedL10n.tr("Untranslated", "screen_onboarding_sign_in_code_rejected_message") }
  /// This sign-in code cannot be used
  internal static var screenOnboardingSignInCodeRejectedTitle: String { return UntranslatedL10n.tr("Untranslated", "screen_onboarding_sign_in_code_rejected_title") }
  /// Search for chats and messages
  internal static var screenSearchEmptyStateMessage: String { return UntranslatedL10n.tr("Untranslated", "screen_search_empty_state_message") }
  /// Start searching...
  internal static var screenSearchEmptyStateTitle: String { return UntranslatedL10n.tr("Untranslated", "screen_search_empty_state_title") }
  /// There are no results for “%1$@.” Try a new search term.
  internal static func screenSearchNoResultsMessage(_ p1: Any) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_search_no_results_message", String(describing: p1))
  }
  /// Chats
  internal static var screenSearchTabChats: String { return UntranslatedL10n.tr("Untranslated", "screen_search_tab_chats") }
  /// Messages
  internal static var screenSearchTabMessages: String { return UntranslatedL10n.tr("Untranslated", "screen_search_tab_messages") }
  /// Clear all data currently stored on this device?
  /// Sign in again to access your account data and messages.
  internal static var softLogoutClearDataDialogContent: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_clear_data_dialog_content") }
  /// Clear data
  internal static var softLogoutClearDataDialogTitle: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_clear_data_dialog_title") }
  /// Warning: Your personal data (including encryption keys) is still stored on this device.
  /// 
  /// Clear it if you’re finished using this device, or want to sign in to another account.
  internal static var softLogoutClearDataNotice: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_clear_data_notice") }
  /// Clear all data
  internal static var softLogoutClearDataSubmit: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_clear_data_submit") }
  /// Clear personal data
  internal static var softLogoutClearDataTitle: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_clear_data_title") }
  /// Sign in to recover encryption keys stored exclusively on this device. You need them to read all of your secure messages on any device.
  internal static var softLogoutSigninE2eWarningNotice: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_signin_e2e_warning_notice") }
  /// Your homeserver (%1$s) admin has signed you out of your account %2$s (%3$s).
  internal static func softLogoutSigninNotice(_ p1: UnsafePointer<CChar>, _ p2: UnsafePointer<CChar>, _ p3: UnsafePointer<CChar>) -> String {
    return UntranslatedL10n.tr("Untranslated", "soft_logout_signin_notice", p1, p2, p3)
  }
  /// Sign in
  internal static var softLogoutSigninTitle: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_signin_title") }
  /// Untranslated
  internal static var untranslated: String { return UntranslatedL10n.tr("Untranslated", "untranslated") }
  /// Plural format key: "%#@VARIABLE@"
  internal static func untranslatedPlural(_ p1: Int) -> String {
    return UntranslatedL10n.tr("Untranslated", "untranslated_plural", p1)
  }
}
// swiftlint:enable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:enable nesting type_body_length type_name vertical_whitespace_opening_braces

// MARK: - Implementation Details

nonisolated extension UntranslatedL10n {
  static func tr(_ table: String, _ key: String, _ args: CVarArg...) -> String {
    // No need to check languages, we always default to en for untranslated strings
    guard let bundle = Bundle.lprojBundle(for: "en") else { return key }
    let format = NSLocalizedString(key, tableName: table, bundle: bundle, comment: "")
    return String(format: format, locale: Locale(identifier: "en"), arguments: args)
  }
}

// swiftlint:enable all
