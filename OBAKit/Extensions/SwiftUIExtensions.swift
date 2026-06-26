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

// MARK: - liquidGlassButtonStyle

public extension View {
    /// Apply to a `Button` to give it Apple's interactive Liquid Glass surface
    /// on iOS 26+ (the press/morph "grab" response that comes with
    /// `.buttonStyle(.glass)`), with a `.plain` + `.regularMaterial` fallback
    /// on older systems so the button still reads as floating.
    ///
    /// Two shape parameters because the two surfaces use different APIs:
    /// `borderShape` drives the iOS 26 glass morphing, `fallbackShape` fills
    /// the pre-26 material background. Pass matching shapes (e.g. `.circle` +
    /// `Circle()`) for a consistent look across versions.
    @ViewBuilder
    func liquidGlassButtonStyle(
        borderShape: ButtonBorderShape = .capsule,
        fallbackShape: some Shape = Capsule()
    ) -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass).buttonBorderShape(borderShape)
        } else {
            self.buttonStyle(.plain).background(.regularMaterial, in: fallbackShape)
        }
    }
}
