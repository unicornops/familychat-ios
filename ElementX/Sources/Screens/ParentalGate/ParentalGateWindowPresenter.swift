//
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import SwiftUI

/// Presents the parental gate as a sheet in its own window above everything else.
///
/// A separate window lets the gate appear from anywhere (SwiftUI sheets, share sheets, Quick Look,
/// secondary windows) without touching SwiftUI's presentation state. The gate is cancelled when the app
/// goes to the background, so coming back to it always starts with a new question.
final class ParentalGateWindowPresenter: ParentalGatePresenterProtocol {
    private var window: UIWindow?
    private var backgroundObserver: AnyCancellable?
    
    func presentGate(for url: URL, completion: @escaping (Bool) -> Void) {
        guard window == nil, let windowScene = Self.activeWindowScene else {
            MXLog.error("Unable to present the parental gate.")
            completion(false)
            return
        }
        
        let previousKeyWindow = windowScene.keyWindow
        let rootViewController = UIViewController()
        rootViewController.view.backgroundColor = .clear
        
        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.tintColor = .compound.textActionPrimary
        window.overrideUserInterfaceStyle = previousKeyWindow?.overrideUserInterfaceStyle ?? .unspecified
        window.rootViewController = rootViewController
        self.window = window
        window.makeKeyAndVisible()
        
        let model = ParentalGateScreenModel(destination: url) { [weak self] passed in
            self?.dismiss(restoringKeyWindow: previousKeyWindow)
            completion(passed)
        }
        
        backgroundObserver = NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { _ in
                model.cancel()
            }
        
        let hostingController = UIHostingController(rootView: ParentalGateScreen(model: model))
        hostingController.modalPresentationStyle = .formSheet
        // Only Cancel or an answer closes the gate, so a swipe can't leave it in an unknown state.
        hostingController.isModalInPresentation = true
        rootViewController.present(hostingController, animated: true)
    }
    
    // MARK: - Private
    
    private static var activeWindowScene: UIWindowScene? {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return windowScenes.first { $0.activationState == .foregroundActive && $0.keyWindow != nil }
            ?? windowScenes.first { $0.activationState == .foregroundActive }
            ?? windowScenes.first
    }
    
    private func dismiss(restoringKeyWindow previousKeyWindow: UIWindow?) {
        backgroundObserver = nil
        
        guard let window else { return }
        self.window = nil
        
        window.rootViewController?.dismiss(animated: true)
        
        // Let the sheet animate away before removing its window.
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
    }
}
