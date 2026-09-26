//
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// The single way Family Chat opens anything outside the app.
///
/// Family Chat is in Apple's Kids Category (guideline 1.3), so every link out of the app sits behind an
/// adult-level challenge (unicornops/family-chat#232 decision 10). **All** code that would otherwise call
/// `UIApplication.open`, present `SFSafariViewController` or use SwiftUI's default `openURL` must call
/// ``openExternalURL(_:completion:)`` instead: web links, `mailto:`/`tel:`/`sms:` and other apps' schemes.
/// That includes the future control panel settings entry and GIF attribution. The `external_url_open`
/// SwiftLint rule flags direct calls.
///
/// URLs the app handles itself (its universal links on `safechat.family/app/…`, matrix.to and other
/// permalinks, its own URL scheme) are routed in-app by ``internalURLHandler`` and never gated, and nor
/// are iOS's own settings pages for this app (``appSettingsURLs``).
/// There is nothing purchasable in the app; anything that ever is must also be gated.
///
/// SwiftUI views get the gate through the `openURL` environment action set up in `Application`; views
/// hosted outside that environment (for example inside a `QLPreviewController`) use ``openURLAction``.
final class ParentalGate {
    enum Outcome: Equatable {
        /// The app handled the URL itself; no gate was shown.
        case handledInternally
        /// iOS's own settings for this app were opened; no gate was shown.
        case openedAppSettings
        /// The challenge was answered and the URL was handed to the system.
        case opened
        /// The gate was cancelled, failed, or another gate was already showing. Nothing was opened.
        case notOpened
    }
    
    static let shared = ParentalGate(presenter: ParentalGateWindowPresenter()) { url in
        UIApplication.shared.open(url, options: [:], completionHandler: nil) // swiftlint:disable:this external_url_open
    }
    
    /// iOS's Settings pages for this app, where permissions and notifications are granted. They aren't a
    /// link out (no external content, nothing to navigate to), so they open without the gate.
    static let appSettingsURLs: Set<URL> = Set([UIApplication.openSettingsURLString,
                                                UIApplication.openNotificationSettingsURLString].compactMap(URL.init(string:)))
    
    /// Routes a URL inside the app, returning `false` when the app can't handle it. Set by `Application`.
    var internalURLHandler: ((URL) -> Bool)?
    
    private let presenter: ParentalGatePresenterProtocol
    private let systemOpener: (URL) -> Void
    private var isPresenting = false
    
    /// An `openURL` action for SwiftUI hierarchies that don't inherit the app's own.
    var openURLAction: OpenURLAction {
        OpenURLAction { [weak self] url in
            self?.openExternalURL(url)
            return .handled
        }
    }
    
    init(presenter: ParentalGatePresenterProtocol,
         internalURLHandler: ((URL) -> Bool)? = nil,
         systemOpener: @escaping (URL) -> Void) {
        self.presenter = presenter
        self.internalURLHandler = internalURLHandler
        self.systemOpener = systemOpener
    }
    
    /// Opens `url` in the app if it is one of the app's own links, otherwise only after the parental gate
    /// has been passed. The URL is never logged: links from messages are user content.
    func openExternalURL(_ url: URL, completion: ((Outcome) -> Void)? = nil) {
        if internalURLHandler?(url) == true {
            completion?(.handledInternally)
            return
        }
        
        if Self.appSettingsURLs.contains(url) {
            systemOpener(url)
            completion?(.openedAppSettings)
            return
        }
        
        guard !isPresenting else {
            MXLog.info("Ignoring an external link while the parental gate is already showing.")
            completion?(.notOpened)
            return
        }
        
        isPresenting = true
        presenter.presentGate(for: url) { [weak self] passed in
            guard let self else { return }
            isPresenting = false
            
            guard passed else {
                MXLog.info("Parental gate not passed, the external link was not opened.")
                completion?(.notOpened)
                return
            }
            
            MXLog.info("Parental gate passed, opening an external link.")
            systemOpener(url)
            completion?(.opened)
        }
    }
}

/// Shows the parental gate UI and reports whether the challenge was answered correctly.
protocol ParentalGatePresenterProtocol {
    func presentGate(for url: URL, completion: @escaping (Bool) -> Void)
}
