//
//  StopPageListHeaderRow.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The Time / Route switch shown in the list header row. Factored out so
/// `StopPageView` stays a thin composition — the mode change side effects
/// (collapse accordions, persist) live in the caller's `onChange`.
///
/// A custom capsule control rather than a segmented `Picker`: taller segments and
/// a Liquid Glass backdrop on iOS 26+ (an ultra-thin-material capsule stands
/// in on earlier versions). The selected pill slides between segments via
/// `matchedGeometryEffect`; the caller's `withAnimation` drives it.
///
/// Sized to its content, not to the row: the design puts it at the trailing end
/// of a row it shares with the Past toggle. `StopPageListHeaderRow` owns that
/// layout.
///
/// Labels are one-word nouns per the HIG's guidance for segmented controls
/// ("Use nouns or noun phrases for segment labels", and keep content a similar
/// size in each segment) — which "Chronological" and "By route" were not.
struct StopPageModeToggle: View {
    let mode: StopSort
    let onChange: (StopSort) -> Void

    @Namespace private var selectionNamespace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At accessibility sizes the two segments stack as full-width rows (the
    /// guide's layout) instead of splitting one line — each label gets the
    /// whole row's width, so neither truncates.
    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        let layout = isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 2))
            : AnyLayout(HStackLayout(spacing: 2))
        layout {
            segment(.time, title: OBALoc("stop_page.mode.time", value: "Time", comment: "Stop page mode toggle: flat time-sorted list"), systemImage: "line.3.horizontal.decrease")
            segment(.route, title: OBALoc("stop_page.mode.route", value: "Route", comment: "Stop page mode toggle: grouped by route"), systemImage: "bus")
        }
        .padding(3)
        .modifier(GlassContainerBackground(usesCapsule: !isAccessibilitySize))
        .frame(maxWidth: isAccessibilitySize ? .infinity : nil)
    }

    private func segment(_ value: StopSort, title: String, systemImage: String) -> some View {
        Button {
            if mode != value { onChange(value) }
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(mode == value ? .bold : .semibold))
                .foregroundStyle(mode == value ? Color.primary : Color.secondary)
                .lineLimit(1)
                // The label reports its full width no matter what the row proposes,
                // so a segment can never answer a tight proposal by truncating to
                // "Ro…". When the row genuinely can't hold both controls side by
                // side, `StopPageListHeaderRow`'s `ViewThatFits` stacks them
                // instead — a wider row rather than a clipped word.
                //
                // Only where that fallback exists. The accessibility branch bypasses
                // `ViewThatFits` entirely, and the segments there already get the
                // whole row's width from the `maxWidth: .infinity` below, so
                // fixing the size would buy nothing and would take away truncation
                // as the last resort for an over-long localization.
                .fixedSize(horizontal: !isAccessibilitySize, vertical: false)
                // A floor rather than a fixed width, so the two segments come out
                // near-equal (the HIG's "keep segment size consistent") without
                // clipping a longer localization of either noun.
                .frame(minWidth: isAccessibilitySize ? nil : 76, maxWidth: isAccessibilitySize ? .infinity : nil, minHeight: 34)
                .padding(.horizontal, isAccessibilitySize ? 0 : 6)
                .background {
                    if mode == value {
                        selectionShape
                            .fill(Color(uiColor: .systemBackground))
                            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                            .matchedGeometryEffect(id: "selectedSegment", in: selectionNamespace)
                    }
                }
                .contentShape(selectionShape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == value ? [.isButton, .isSelected] : [.isButton])
    }

    /// Capsule segments inside the capsule container; rounded rectangles when
    /// the segments stack (a capsule around a multi-line label reads poorly).
    private var selectionShape: AnyShape {
        isAccessibilitySize
            ? AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            : AnyShape(Capsule())
    }
}

/// The row above the departure list: the Past disclosure on the leading edge, the
/// mode toggle on the trailing one.
///
/// The two used to sit on separate rows, with the toggle spanning the full width
/// and the Past control tucked into a section header beside an "Arrivals &
/// Departures" title. That title is gone: it names the one thing the sheet is
/// unambiguously showing, and the sheet's vertical budget is the scarce resource
/// here.
struct StopPageListHeaderRow: View {
    let mode: StopSort
    /// Zero in grouped mode, which has no past partition — the leading half of
    /// the row is then simply empty.
    let pastCount: Int
    let showPast: Bool
    let onTogglePast: () -> Void
    let onChangeMode: (StopSort) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        Group {
            // Stacked at accessibility sizes: the toggle already goes full-width and
            // two-line there, so keeping the Past control beside it would leave it a
            // sliver.
            if isAccessibilitySize {
                stacked
            } else {
                // Neither control may truncate (both are one-word-ish tokens that
                // stop meaning anything clipped), so when the two can't share a
                // line — a long localization, a narrow device, a large-but-not-yet-
                // accessibility type size — they get a line each instead.
                ViewThatFits(in: .horizontal) {
                    sideBySide
                    stacked
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var sideBySide: some View {
        HStack(spacing: 12) {
            if pastCount > 0 {
                pastButton
            }
            Spacer(minLength: 0)
            StopPageModeToggle(mode: mode, onChange: onChangeMode)
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 8) {
            if pastCount > 0 {
                pastButton
            }
            StopPageModeToggle(mode: mode, onChange: onChangeMode)
        }
    }

    /// A capsule with a chevron, not bare bold text. As a label alone it read as a
    /// section heading — nothing about "Past · 1" said it would open anything — so
    /// it borrows the header's chip vocabulary for its shape and the app tint for
    /// its content. The fill stays neutral (`secondarySystemFill`); only the text
    /// and chevron take the tint.
    ///
    /// The chevron follows the conventional disclosure direction — down closed, up
    /// open — rather than pointing at the disclosed rows, which are below.
    private var pastButton: some View {
        Button(action: onTogglePast) {
            HStack(spacing: 5) {
                Text(showPast
                     ? OBALoc("stop_page.past_toggle_hide", value: "Hide past", comment: "Button hiding recently departed trips")
                     : String(format: OBALoc("stop_page.past_toggle_fmt", value: "Past · %d", comment: "Button revealing recently departed trips. %d is the count."), pastCount))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    // Same reason as the toggle's segments: the count and the verb
                    // are the whole message, so the row grows or wraps rather than
                    // clipping either.
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .rotationEffect(.degrees(showPast ? 180 : 0))
                    .accessibilityHidden(true) // decorative; the label carries the state
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(Color(uiColor: .secondarySystemFill), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // The visible "Past · 3" is a glanceable token; spoken aloud it needs to
        // say what activating actually does.
        .accessibilityLabel(showPast
            ? OBALoc("stop_page.past_toggle_hide_a11y", value: "Hide past departures", comment: "VoiceOver label for the button hiding recently departed trips")
            : String(format: OBALoc("stop_page.past_toggle_show_a11y_fmt", value: "Show %d past departures", comment: "VoiceOver label for the button revealing recently departed trips. %d is the count. Plural forms live in Localizable.stringsdict; the value above is only the not-found fallback."), pastCount))
    }
}

/// The toggle's backdrop: real Liquid Glass on iOS 26+, an ultra-thin-material
/// shape with a hairline rim on earlier versions. Capsule by default; a
/// rounded rectangle when the segments stack at accessibility sizes.
///
/// Internal rather than file-private: `StopPageFooterSection`'s "Load more"
/// capsule deliberately echoes this same backdrop.
struct GlassContainerBackground: ViewModifier {
    let usesCapsule: Bool

    private var shape: AnyShape {
        usesCapsule ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5))
        }
    }
}
