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

// MARK: - Glass circle chrome

private enum GlassCircleMetrics {
    /// The HIG's minimum comfortable tap target.
    static let minimumTouchTarget: CGFloat = 44
}

/// The stop sheet's chrome circles — the action row's four controls, the top
/// bar's Refresh and Close, and the floating scroll-to-top button — are one
/// visual system rendered at three sizes.
///
/// Two modifiers rather than one because the pieces attach to different views.
/// The surface goes on the control, which is a `Menu` as often as a `Button`,
/// so a helper that built the `Button` itself would not cover half the call
/// sites. The size and hit region go on the *label*, inside the control:
/// `.contentShape` only defines a button's tappable area from within it, and a
/// fixed frame applied outside `.buttonStyle(.glass)` would clamp the glass
/// surface the style draws instead of the glyph it wraps.
public extension View {

    /// Sizes the glyph a glass circle wraps, and gives the control a 44pt hit
    /// region no matter how small the circle looks.
    ///
    /// The visual size stays `diameter`; only the interaction shape grows. On
    /// iOS 26 `.buttonStyle(.glass)` pads the label, so the real control is
    /// already comfortable — but the pre-26 fallback (`.plain` plus a
    /// `.regularMaterial` background) adds no padding at all, leaving the hit
    /// region exactly the shape declared here. Our deployment target is 18.0,
    /// so that fallback is the majority path today, and without the outset a
    /// 32pt circle really is a 32pt target.
    func glassCircleLabel(diameter: CGFloat) -> some View {
        let outset = max(0, GlassCircleMetrics.minimumTouchTarget - diameter) / 2
        return self
            .frame(width: diameter, height: diameter)
            .contentShape(.interaction, Circle().inset(by: -outset))
    }

    /// The interactive Liquid Glass surface every chrome circle wears.
    ///
    /// `.tint`, not `.foregroundStyle`: the glass button style colours its
    /// content from the tint, so the chrome reads as neutral rather than as a
    /// row of tinted calls to action — and disabled dimming still applies,
    /// which hard-coding `.primary` above the control would defeat.
    func glassCircleSurface() -> some View {
        self
            .liquidGlassButtonStyle(borderShape: .circle, fallbackShape: Circle())
            .tint(.primary)
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

// MARK: - MapLabelOutline

/// Wraps `content` in a `color` outline ring — a SwiftUI stand-in for a glyph
/// stroke (which `Text` can't render), used to keep map labels legible over the
/// muted map the way the UIKit map's `NSAttributedString` stroke does.
///
/// Takes a `@ViewBuilder` closure rather than a `ViewModifier` so `content` is a
/// value we can legitimately instantiate for each offset copy — invoking a
/// ViewBuilder closure multiple times is supported, whereas reusing a
/// `ViewModifier.Content` proxy across a body is not. The whole ring is drawn
/// into a single rasterized layer via `.drawingGroup()`, so a dense viewport
/// pays one composited layer per label instead of nine.
struct MapLabelOutline<Content: View>: View {
    let color: Color
    /// Outline radius, in points.
    var width: CGFloat = 1
    @ViewBuilder let content: () -> Content

    /// Eight evenly-spaced offsets around a `width`-radius circle — enough
    /// samples to read as a continuous ring at label point sizes.
    private var offsets: [CGSize] {
        (0..<8).map { i in
            let angle = Double(i) / 8 * 2 * .pi
            return CGSize(width: cos(angle) * width, height: sin(angle) * width)
        }
    }

    var body: some View {
        content()
            .background {
                ZStack {
                    ForEach(offsets.indices, id: \.self) { index in
                        // Masking (rather than recoloring) keeps every copy the
                        // outline color regardless of the content's own style.
                        color
                            .mask { content() }
                            .offset(offsets[index])
                    }
                }
            }
            .drawingGroup()
    }
}
