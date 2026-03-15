//
//  ToastView+UIViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

// MARK: - UIKit Extension
extension UIViewController {

    private static var toastWindow: UIWindow?

    // MARK: - Public API

    /// Shows a success toast. Pass `manager` to share the same ToastManager
    /// instance that your SwiftUI views are observing (e.g. `application.toastManager`).
    func showSuccessToast(_ message: String?, using manager: ToastManager, duration: TimeInterval = 3.0) {
        guard let message, !message.isEmpty else { return }
        showToast(message: message, type: .success, using: manager, duration: duration)
    }

    /// Shows an error toast. Pass `manager` to share the same ToastManager
    /// instance that your SwiftUI views are observing (e.g. `application.toastManager`).
    func showErrorToast(_ message: String?, using manager: ToastManager, duration: TimeInterval = 3.0) {
        guard let message, !message.isEmpty else { return }
        showToast(message: message, type: .error, using: manager, duration: duration)
    }

    // MARK: - Private

    private func showToast(message: String, type: Toast.ToastType, using manager: ToastManager, duration: TimeInterval) {
        guard let windowScene = view.window?.windowScene else { return }

        createToastWindowIfNeeded(windowScene, manager: manager)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.5) {
            UIViewController.toastWindow = nil
        }

        switch type {
        case .success:
            manager.showSuccess(message, duration: duration)
        case .error:
            manager.showError(message, duration: duration)
        }
    }

    private func createToastWindowIfNeeded(_ windowScene: UIWindowScene, manager: ToastManager) {
        guard UIViewController.toastWindow == nil else { return }

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = false

        let hostingController = UIHostingController(
            rootView: ToastContainerView().environmentObject(manager)
        )

        hostingController.view.backgroundColor = .clear
        window.rootViewController = hostingController
        window.isHidden = false

        UIViewController.toastWindow = window
    }
}

// MARK: - Toast Container View for UIKit
struct ToastContainerView: View {
    @EnvironmentObject var manager: ToastManager

    var body: some View {
        if let toast = manager.toast {
            VStack {
                ToastView(toast: toast)
                    .offset(y: manager.isShowing ? 0 : -150)
                    .opacity(manager.isShowing ? 1 : 0)
                    .padding(.top, 60)

                Spacer()
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: manager.isShowing)
            .ignoresSafeArea()
        }
    }
}
