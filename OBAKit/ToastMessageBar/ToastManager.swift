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
import UIKit

class ToastManager: ObservableObject {

    @Published var toast: Toast?
    @Published var isShowing: Bool = false
    private var workItem: DispatchWorkItem?

    init() {}

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

        // The toast never takes focus, so VoiceOver would not otherwise read it.
        AccessibilityAnnouncement.post(toast.message)

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
        let dwell = Self.dwell(for: toast.duration, isVoiceOverRunning: UIAccessibility.isVoiceOverRunning)
        DispatchQueue.main.asyncAfter(deadline: .now() + dwell, execute: task)
    }

    /// The minimum time a toast stays up under VoiceOver.
    static let minimumVoiceOverDwell: TimeInterval = 8

    /// How long a toast stays on screen. A VoiceOver user hears the message
    /// queued behind whatever is already being spoken, and may then want to swipe
    /// to it, so the toast stays at least `minimumVoiceOverDwell` seconds rather
    /// than vanishing mid-sentence.
    static func dwell(for requested: TimeInterval, isVoiceOverRunning: Bool) -> TimeInterval {
        isVoiceOverRunning ? max(requested, minimumVoiceOverDwell) : requested
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
