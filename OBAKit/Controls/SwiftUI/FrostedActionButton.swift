//
//  FrostedActionButton.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// The frosted shape behind an action-bar control: `Material` — the
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
/// style: the "More" item on the Stop page toolbar and the Trip page bar has to
/// apply this to its label directly. Buttons should use `FrostedActionButtonStyle` instead, which adds
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
///
/// A capsule by default. The trip page's bar passes a rounded rectangle instead:
/// its captions wrap to two lines, and a capsule that tall curves in most of the
/// way down its sides, under the text.
struct FrostedBackground<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            // Two fills in the builder's implicit ZStack rather than a nested
            // overlay: same result, one less layer to reason about.
            .background {
                shape.fill(.regularMaterial)
                shape.fill(Color(uiColor: .tertiarySystemFill))
            }
            .overlay(
                shape.strokeBorder(Color(uiColor: .separator).opacity(0.6), lineWidth: 0.5)
            )
            .contentShape(shape)
    }
}

extension FrostedBackground where S == Capsule {
    init() { self.init(shape: Capsule()) }
}

/// A button drawn on a `FrostedBackground` with a full-strength `label` foreground.
///
/// The foreground is deliberately `.label` rather than the app tint: tinted
/// glyphs on the near-white bar these sit on is the low-contrast treatment this
/// style exists to replace. The shape carries the affordance; the content
/// carries the meaning.
///
/// `.bordered` — which this stands in for — dimmed itself when pressed and when
/// disabled. A custom style gets neither for free, so both are stated here.
struct FrostedActionButtonStyle<S: InsettableShape>: ButtonStyle {
    let shape: S
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(uiColor: .label))
            .modifier(FrostedBackground(shape: shape))
            .opacity(opacity(isPressed: configuration.isPressed))
    }

    private func opacity(isPressed: Bool) -> Double {
        if !isEnabled { return 0.4 }
        return isPressed ? 0.55 : 1
    }
}

extension FrostedActionButtonStyle where S == Capsule {
    init() { self.init(shape: Capsule()) }
}
