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

    func showSuccessToast(_ message: String?, duration: TimeInterval = 3.0) {
        guard let message, !message.isEmpty else { return }
        showToast(message: message, type: .success, duration: duration)
    }

    func showErrorToast(_ message: String?, duration: TimeInterval = 3.0) {
        guard let message, !message.isEmpty else { return }
        showToast(message: message, type: .error, duration: duration)
    }

    private func showToast(message: String, type: Toast.ToastType, duration: TimeInterval) {
        guard let windowScene = view.window?.windowScene else { return }

        createToastWindowIfNeeded(windowScene)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.5) {
            UIViewController.toastWindow = nil
        }

        showToastFor(type, message: message, duration: duration)
    }

    private func createToastWindowIfNeeded(_ windowScene: UIWindowScene) {
        if UIViewController.toastWindow == nil {
            let window = UIWindow(windowScene: windowScene)
            window.windowLevel = .alert
            window.backgroundColor = .clear
            window.isUserInteractionEnabled = false

            let hostingController = UIHostingController(rootView: ToastContainerView())
            hostingController.view.backgroundColor = .clear
            window.rootViewController = hostingController
            window.isHidden = false

            UIViewController.toastWindow = window
        }
    }

    private func showToastFor(_ type: Toast.ToastType, message: String, duration: TimeInterval) {
        switch type {
        case .success:
            ToastManager.shared.showSuccess(message, duration: duration)
        case .error:
            ToastManager.shared.showError(message, duration: duration)
        }
    }

}

// MARK: - Toast Container View for UIKit
struct ToastContainerView: View {
    @ObservedObject var manager = ToastManager.shared

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
