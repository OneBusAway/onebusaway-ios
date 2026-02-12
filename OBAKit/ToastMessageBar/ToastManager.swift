//
//  ToastManager.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import SwiftUI

class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var toast: Toast?
    @Published var isShowing: Bool = false
    private var workItem: DispatchWorkItem?

    private init() {}

    func showSuccess(_ message: String, duration: TimeInterval = 3.0) {
        let toast = Toast(message: message, type: .success, duration: duration)
        show(toast)
    }

    func showError(_ message: String, duration: TimeInterval = 3.0) {
        let toast = Toast(message: message, type: .error, duration: duration)
        show(toast)
    }

    private func show(_ toast: Toast) {
        self.toast = toast

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            self.isShowing = true
        }

        workItem?.cancel()
        let task = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self?.isShowing = false
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.toast = nil
            }
        }
        workItem = task
        DispatchQueue.main.asyncAfter(deadline: .now() + toast.duration, execute: task)
    }

    func dismiss() {
        workItem?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isShowing = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.toast = nil
        }
    }
}
