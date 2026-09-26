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
/// ``openExternalURL(_:completion:)`` instead (or `AppMediatorProtocol.open`, which calls it): web links,
/// `mailto:`/`tel:`/`sms:` and other apps' schemes. That includes the future control panel settings entry
/// and GIF attribution. The `external_url_open` SwiftLint rule flags direct calls.
///
/// URLs the app routes itself (whatever `AppRouteURLParser` recognises: matrix.to and other permalinks,
/// `app.safechat.family` links, `safechat.family` links carrying `account_provider`, the app's own scheme)
/// go to ``internalURLHandler`` and are never gated, and nor are iOS's own settings pages for this app
/// (``appSettingsURLs``). There is nothing purchasable in the app; anything that ever is must also be gated.
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
    
    /// Hosts in the app's `applinks` entitlement. Links to them get `no_universal_links=true` once the gate
    /// is passed so iOS sends them to the browser instead of back into the app (and through the gate twice);
    /// the AASA must exclude that query item for this to work.
    static let universalLinkHosts: Set = ["safechat.family", "app.safechat.family"]
    
    /// iOS's Settings pages for this app, where permissions and notifications are granted. They aren't a
    /// link out (no external content, nothing to navigate to), so they open without the gate.
    static let appSettingsURLs: Set<URL> = Set([UIApplication.openSettingsURLString,
                                                UIApplication.openNotificationSettingsURLString].compactMap(URL.init(string:)))
    
    /// Only for callers that can't be handed a gate: Quick Look delegates, `UIActivity` and app start-up.
    static let shared = ParentalGate(presenter: ParentalGateWindowPresenter()) { url in
        UIApplication.shared.open(url, options: [:], completionHandler: nil) // swiftlint:disable:this external_url_open
    }
    
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
    /// has been passed. Links the phishing detector wrapped (link text that looks like a different URL) are
    /// unwrapped and the gate warns about the mismatch. The URL is never logged: links are user content.
    func openExternalURL(_ url: URL, completion: ((Outcome) -> Void)? = nil) {
        let confirmation = url.confirmationParameters
        let destination = confirmation?.internalURL ?? url
        
        if internalURLHandler?(destination) == true {
            completion?(.handledInternally)
            return
        }
        
        if Self.appSettingsURLs.contains(destination) {
            systemOpener(destination)
            completion?(.openedAppSettings)
            return
        }
        
        guard !isPresenting else {
            MXLog.info("Ignoring an external link while the parental gate is already showing.")
            completion?(.notOpened)
            return
        }
        
        isPresenting = true
        presenter.presentGate(for: destination, linkText: confirmation?.displayString) { [weak self] passed in
            guard let self else { return }
            isPresenting = false
            
            guard passed else {
                MXLog.info("Parental gate not passed, the external link was not opened.")
                completion?(.notOpened)
                return
            }
            
            MXLog.info("Parental gate passed, opening an external link.")
            systemOpener(Self.browserURL(for: destination))
            completion?(.opened)
        }
    }
    
    /// `url`, with `no_universal_links=true` added when it is on one of the app's own universal link hosts.
    static func browserURL(for url: URL) -> URL {
        guard let host = url.host()?.lowercased(),
              universalLinkHosts.contains(host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        
        var queryItems = components.queryItems ?? []
        guard !queryItems.contains(where: { $0.name == "no_universal_links" }) else {
            return url
        }
        queryItems.append(URLQueryItem(name: "no_universal_links", value: "true"))
        components.queryItems = queryItems
        return components.url ?? url
    }
}

/// Shows the parental gate UI and reports whether the challenge was answered correctly.
protocol ParentalGatePresenterProtocol {
    /// - Parameters:
    ///   - url: Where the link goes.
    ///   - linkText: The text the link was shown as, when it looks like a different URL.
    func presentGate(for url: URL, linkText: String?, completion: @escaping (Bool) -> Void)
}
