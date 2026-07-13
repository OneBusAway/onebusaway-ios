//
//  SwiftUIExtensions.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/16/23.
//

import SwiftUI
import UIKit
import OBAKitCore

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

    /// More transparent variant of `glassEffect` (iOS 26+). Use for surfaces
    /// that should let more of the background through (large cards, sheets).
    /// Falls back to a solid themed fill pre-iOS 26 — no half-glass middle
    /// ground.
    ///
    /// Unlike `regularGlassEffectIfAvailable`, this variant does **not** form a
    /// self-contained surface: on iOS 26 the clear glass needs a backing fill
    /// to read against, so call sites should layer their own
    /// `.ultraThinMaterial` (or similar) underneath. See
    /// `WeatherDetailPopup.WeatherCard` for the expected stacking.
    @ViewBuilder
    func clearGlassEffectIfAvailable(in shape: some Shape = Capsule()) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.clear, in: shape)
        } else {
            self.background(Color(uiColor: .secondarySystemBackground), in: shape)
        }
    }
}

extension View {
   /// Lifts an overlay above the floating sheet and syncs its opacity /
   /// animation with the sheet's live drag height, so the bottom-leading
   /// (trip) and bottom-trailing (map controls) toolbars move together as
   /// the user drags. Callers still apply their own leading/trailing padding.
   func floatingOverSheet(height: CGFloat, opacity: CGFloat, duration: CGFloat) -> some View {
       self
           .padding(.bottom, height + ThemeMetrics.padding)
           .opacity(opacity)
           .animation(
               .interpolatingSpring(duration: duration, bounce: 0, initialVelocity: 0),
               value: height
           )
   }
}
