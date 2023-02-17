//
//  OnboardingView.swift
//  OBAKit
//
//  Created by Alan Chu on 1/27/23.
//

import SwiftUI
import OBAKitCore
import CoreLocationUI

// As of iOS 15/16, there is no way to set a custom `@Environment(\.dismiss)`.
// While Onboarding, we don't want the views to `dismiss` normally.
public protocol OnboardingView: View {
    /// When dismissing itself, the View should use `dismissBlock()`, or `@Environment(\.dismiss)` if the former is `nil`.
    var dismissBlock: VoidBlock? { get set }

    /// `@Environment(\.dismiss)`
    var dismissAction: DismissAction { get }

    @MainActor func dismiss()
}

extension OnboardingView where Self: View {
    @MainActor public func dismiss() {
        if let dismissBlock {
            dismissBlock()
        } else {
            dismissAction()
        }
    }
}
