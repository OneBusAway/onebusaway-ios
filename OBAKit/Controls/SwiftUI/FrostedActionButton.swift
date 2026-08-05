//
//  FrostedActionButton.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// The frosted capsule behind an action-bar control: `Material` — the
/// `UIVisualEffectView` blur — with a translucent fill over it and a hairline rim.
///
/// The blur alone is not enough where these are used, and measuring says so: a
/// bare `.regularMaterial` capsule resolves to within ~6/255 of the bar it sits
/// on, because the bar is itself a material sampling the same backdrop, so the
/// two land on nearly the same value and the capsule all but disappears. The
/// `tertiarySystemFill` over the blur is what gives it an edge, taking the
/// capsule to ~20/255 — enough to read as a control at 1x rather than only under
/// magnification. Being a system *fill*, it stays semi-transparent, so the blur
/// underneath still does its work.
///
/// A `ViewModifier` and not only a `ButtonStyle` because `Menu` takes no button
/// style: the Stop page toolbar's "More" item has to apply this to its label
/// directly. Buttons should use `FrostedActionButtonStyle` instead, which adds
/// the pressed and disabled states on top of this.
///
/// Deliberately flat `Material` rather than Liquid Glass. The rest of this app's
/// capsules go through `GlassContainerBackground` or
/// `regularGlassEffectIfAvailable(in:)`, both of which use `glassEffect` on
/// iOS 26+; these two bars were specified as a plain frosted visual-effect
/// surface instead, so on iOS 26 they stay flat while the Stop page's mode
/// toggle and "Load more" chip above them render as glass. That split is
/// intentional. The measured contrast figures above were taken against material
/// and would need retaking if this ever moves to glass.
struct FrostedCapsuleBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            // Two fills in the builder's implicit ZStack rather than a nested
            // overlay: same result, one less layer to reason about.
            .background {
                Capsule().fill(.regularMaterial)
                Capsule().fill(Color(uiColor: .tertiarySystemFill))
            }
            .overlay(
                Capsule().strokeBorder(Color(uiColor: .separator).opacity(0.6), lineWidth: 0.5)
            )
            .contentShape(Capsule())
    }
}

/// A button drawn as a frosted capsule with a full-strength `label` foreground.
///
/// The foreground is deliberately `.label` rather than the app tint: tinted
/// glyphs on the near-white bar these sit on is the low-contrast treatment this
/// style exists to replace. The capsule carries the affordance; the content
/// carries the meaning.
///
/// `.bordered` — which this stands in for — dimmed itself when pressed and when
/// disabled. A custom style gets neither for free, so both are stated here.
struct FrostedActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(uiColor: .label))
            .modifier(FrostedCapsuleBackground())
            .opacity(opacity(isPressed: configuration.isPressed))
    }

    private func opacity(isPressed: Bool) -> Double {
        if !isEnabled { return 0.4 }
        return isPressed ? 0.55 : 1
    }
}
