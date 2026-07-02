//
//  SwiftUIExtensions.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/16/23.
//

import SwiftUI

// MARK: - onFirstAppear

// https://www.swiftjectivec.com/swiftui-run-code-only-once-versus-onappear-or-task/
public extension View {
    func onFirstAppear(_ action: @escaping () -> Void) -> some View {
        modifier(FirstAppear(action: action))
    }
}

private struct FirstAppear: ViewModifier {
    let action: () -> Void

    // Use this to only fire your block one time
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        // And then, track it here
        content.onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            action()
        }
    }
}

// MARK: - glassEffectIfAvailable

public extension View {
    /// Applies the iOS 26+ Liquid Glass effect when available, falling back to
    /// `.regularMaterial` on older systems. Handles the surface fill itself —
    /// call sites do not need to add a background.
    @ViewBuilder
    func regularGlassEffectIfAvailable(in shape: some Shape = Capsule()) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}
