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
/// secondary windows) without touching SwiftUI's presentation state. It is shown in the scene holding the
/// key window and cancelled when that scene goes to the background or is disconnected, so the gate can't
/// be left waiting forever and coming back to it always starts with a new question.
final class ParentalGateWindowPresenter: ParentalGatePresenterProtocol {
    private let notificationCenter: NotificationCenter
    private let windowSceneProvider: @MainActor () -> UIWindowScene?
    
    private var window: UIWindow?
    private var sceneObserver: AnyCancellable?
    
    /// Whether a gate is currently on screen.
    var isPresenting: Bool {
        window != nil
    }
    
    init(notificationCenter: NotificationCenter = .default,
         windowSceneProvider: @escaping @MainActor () -> UIWindowScene? = ParentalGateWindowPresenter.keyWindowScene) {
        self.notificationCenter = notificationCenter
        self.windowSceneProvider = windowSceneProvider
    }
    
    func presentGate(for url: URL, linkText: String?, completion: @escaping (Bool) -> Void) {
        guard window == nil, let windowScene = windowSceneProvider() else {
            MXLog.error("Unable to present the parental gate.")
            completion(false)
            return
        }
        
        let previousKeyWindow = windowScene.windows.first(where: \.isKeyWindow)
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
        
        let model = ParentalGateScreenModel(destination: url, linkText: linkText) { [weak self] passed in
            self?.dismiss(restoringKeyWindow: previousKeyWindow)
            completion(passed)
        }
        
        sceneObserver = notificationCenter.publisher(for: UIScene.didEnterBackgroundNotification, object: windowScene)
            .merge(with: notificationCenter.publisher(for: UIScene.didDisconnectNotification, object: windowScene))
            .sink { _ in
                model.cancel()
            }
        
        let hostingController = UIHostingController(rootView: ParentalGateScreen(model: model))
        hostingController.modalPresentationStyle = .formSheet
        // Only Cancel or an answer closes the gate, so a swipe can't leave it in an unknown state.
        hostingController.isModalInPresentation = true
        rootViewController.present(hostingController, animated: true)
    }
    
    /// The foreground scene that holds the key window, so the gate appears where the user tapped on iPad and Mac.
    static func keyWindowScene() -> UIWindowScene? {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return windowScenes.first { $0.activationState == .foregroundActive && $0.windows.contains(where: \.isKeyWindow) }
            ?? windowScenes.first { $0.windows.contains(where: \.isKeyWindow) }
            ?? windowScenes.first { $0.activationState == .foregroundActive }
    }
    
    // MARK: - Private
    
    private func dismiss(restoringKeyWindow previousKeyWindow: UIWindow?) {
        sceneObserver = nil
        
        guard let window else { return }
        self.window = nil
        
        window.rootViewController?.dismiss(animated: true)
        
        // Let the sheet animate away before removing its window.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            window.isHidden = true
            // A new gate may have been opened meanwhile; it keeps the key window.
            if self?.window == nil {
                previousKeyWindow?.makeKey()
            }
        }
    }
}
