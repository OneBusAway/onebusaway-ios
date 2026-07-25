//
//  StopPageSheetHeaderView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// Geometry shared between the collapsed sheet header and the panel layout that has to leave
/// room for it.
///
/// `StopSheetPresenter` sizes its `.tip` detent from `collapsedHeight(for:)` rather than taking
/// FloatingPanel's stock 69 pt. A detent shorter than its header doesn't merely crop the header:
/// SwiftUI pins a `safeAreaInset(edge: .top)` view's *bottom* edge to the clamped inset boundary
/// and lets the rest overflow upward, off the top of the sheet — so the first things to leave the
/// screen are the stop name and the close button, the two the rider most needs there.
nonisolated enum StopSheetHeaderMetrics {
    static let topPadding: CGFloat = 4
    static let collapsedBottomPadding: CGFloat = 10
    /// The close button's fixed size, and so the floor on the collapsed header's content row.
    static let closeButtonSize: CGFloat = 30

    /// The height `StopPageSheetHeaderView(isCollapsed: true)` needs: one line of the stop name
    /// (or the close button, whichever is taller), its padding, and the divider hairline.
    static func collapsedHeight(for traitCollection: UITraitCollection) -> CGFloat {
        let nameLine = UIFont.preferredFont(forTextStyle: .title2, compatibleWith: traitCollection).lineHeight
        return topPadding + max(closeButtonSize, ceil(nameLine)) + collapsedBottomPadding + 1
    }
}

/// The Stop page header used when the page is presented as a sheet over the map.
///
/// Where `StopPageHeaderView` is a full-bleed dark map card — the right call when the page
/// replaces the map wholesale on a push — this variant is light and compact, because the map is
/// already visible directly above the sheet. Repeating it inside the header would spend the
/// sheet's scarce vertical space showing the rider something they can see by looking up.
///
/// Two other things move out of here relative to the dark card: there is no "Updated: …" status
/// line (the sheet's bottom toolbar carries freshness on its refresh item), and the walk pill is
/// tinted rather than solid, since it no longer has to hold up against a photographic backdrop.
///
/// A plain-value view — it never touches `StopViewModel`.
struct StopPageSheetHeaderView: View {
    let stop: Stop
    let walkTime: WalkTimeInfo?
    /// Opens walking directions to the stop (VC-owned; disambiguates between maps apps when more
    /// than one is available).
    let onWalkingDirections: () -> Void
    /// Dismisses the sheet. The close button lives here rather than in a navigation bar: the
    /// sheet's root has no bar (see `StopSheetPresenter`), because a bar would impose a top safe
    /// area on the hosting controller that this header would absorb as dead space above the name.
    let onClose: () -> Void
    /// `true` at the sheet's `.tip` detent, where the header has roughly one row's worth of
    /// height to work with. See `collapsedHeight` for what has to survive that budget and why.
    var isCollapsed = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var subtitle: String {
        Formatters.formattedCodeAndDirection(stop: stop)
    }

    /// Sorted, de-duplicated route short names for the badge row. Mirrors
    /// `Formatters.formattedRoutes`' filtering (some agencies omit short names).
    private var routeBadgeNames: [String] {
        var seen = Set<String>()
        return stop.routes
            .map(\.shortName)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// How many lines the stop name gets. Collapsed the header has one row to spend, so a
    /// second line would push the close button's row past the detent and clip both.
    private var nameLineLimit: Int {
        if isCollapsed { return 1 }
        // Accessibility sizes get more lines so the full name still reads instead of clipping
        // at the larger glyph sizes.
        return dynamicTypeSize.isAccessibilitySize ? 4 : 2
    }

    var body: some View {
        // `spacing: 0` with an explicit trailing `Divider()`: inside a VStack the divider is
        // unambiguously horizontal, where an `.overlay` gives it no axis to infer one from.
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                // The close button shares the name's line rather than sitting above it, so the
                // header costs no vertical space beyond its content.
                HStack(alignment: .top, spacing: 12) {
                    // Name and stop code/direction combined into one VoiceOver element — they
                    // describe one identity and should be read as a unit rather than two
                    // separate focus stops.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stop.name)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(nameLineLimit)
                            .fixedSize(horizontal: false, vertical: true)

                        if !isCollapsed {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)

                    StopSheetCloseButton(action: onClose)
                }

                if let walkTime, !isCollapsed {
                    walkPill(walkTime)
                }

                if !isCollapsed, !routeBadgeNames.isEmpty {
                    // `FlowLayout` only ever receives `Text` here. It sizes subviews with an
                    // unspecified proposal, which a `Button` answers with a greedy height — that
                    // is what stretched the walk pill down the whole sheet, so the pill lives in
                    // a plain stack above instead.
                    FlowLayout(hSpacing: 6, vSpacing: 6) {
                        ForEach(routeBadgeNames, id: \.self) { name in
                            routeBadge(name)
                        }
                    }
                    // One element reading the whole route list, so VoiceOver doesn't walk a dozen
                    // bare numbers with no indication of what they are.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(routeListAccessibilityLabel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, StopSheetHeaderMetrics.topPadding)
            .padding(.bottom, isCollapsed ? StopSheetHeaderMetrics.collapsedBottomPadding : 14)

            // Separates the identity block from the scrolling departures below it. The sheet has
            // no nav bar hairline to do this job — the chrome moved to the bottom toolbar.
            Divider()
        }
        .background(Color(uiColor: .systemBackground))
    }

    /// The walk-time pill: a tinted capsule rather than the dark card's solid green one. The
    /// foreground keeps the full-strength on-time color, which is already tuned per-appearance
    /// for legibility at small sizes (see `ThemeColors.departureOnTime`).
    private func walkPill(_ info: WalkTimeInfo) -> some View {
        Button(action: onWalkingDirections) {
            // An explicit `HStack` rather than a `Label`, and the no-wrap constraint sits on the
            // `Text` rather than on the button.
            //
            // `.fixedSize()` on the enclosing `Button` did not hold: the pill still came out
            // 60pt wide and 168pt tall, with "2 min walk" broken one character per line. Pinning
            // the text itself to a single unwrappable line makes the pill's width a function of
            // its content, which is the property that was actually missing.
            HStack(spacing: 4) {
                Image(systemName: "figure.walk")
                    .accessibilityHidden(true) // the text below carries the meaning
                Text(walkPillText(info))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(uiColor: ThemeColors.shared.departureOnTime))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(uiColor: ThemeColors.shared.departureOnTime).opacity(0.14), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(OBALoc("stop_page.header.walk_a11y_hint", value: "Opens walking directions to this stop.", comment: "VoiceOver hint on the header card's walk-time button."))
    }

    private func routeBadge(_ name: String) -> some View {
        Text(name)
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func walkPillText(_ info: WalkTimeInfo) -> String {
        let fmt = OBALoc(
            "stop_page.walk_chip_minutes_fmt",
            value: "%d min walk",
            comment: "Walk chip on the header card. %d is the walk time in minutes."
        )
        return String(format: fmt, info.walkMinutes)
    }

    private var routeListAccessibilityLabel: String {
        Formatters.formattedRoutes(stop.routes) ?? routeBadgeNames.joined(separator: ", ")
    }
}

/// The sheet's dismissal control, drawn like the system's own sheet close button (a filled circle
/// with a secondary glyph) rather than in the page's tint, so it reads as chrome and not as an
/// action on the stop. Shared by the real header and its stop-unknown stand-in — every state of
/// the sheet has to offer a way out, since there is no navigation bar behind it.
struct StopSheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: StopSheetHeaderMetrics.closeButtonSize, height: StopSheetHeaderMetrics.closeButtonSize)
                .background(Color(uiColor: .secondarySystemFill), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.close)
    }
}

/// The sheet header shown while `Stop` is still unknown — a stop opened by bare ID (Recents, deep
/// links) has no model until the first fetch returns.
///
/// With `showsSkeleton` it is a pulsing stand-in mirroring the real header's block order, so the
/// sheet opens with its final shape instead of jumping when the name arrives. Without it — a first
/// fetch that failed — only the close button remains: a loading skeleton above an error message
/// reads as two contradictory states, but the rider still needs a way out of a stop that will
/// never resolve.
struct StopPageSheetHeaderPlaceholderView: View {
    /// `false` once a first fetch has failed; the centered error row below owns the screen.
    var showsSkeleton = true
    let onClose: () -> Void
    /// `true` at the sheet's `.tip` detent. Trims the skeleton to its name line so the strip
    /// costs the same height the real collapsed header does.
    var isCollapsed = false

    @ScaledMetric(relativeTo: .title2) private var nameLineHeight: CGFloat = 24
    @ScaledMetric(relativeTo: .subheadline) private var subtitleLineHeight: CGFloat = 20

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsSkeleton {
                skeleton
            } else {
                Spacer(minLength: 0)
            }

            StopSheetCloseButton(action: onClose)
        }
        .padding(.horizontal, 16)
        .padding(.top, StopSheetHeaderMetrics.topPadding)
        .padding(.bottom, isCollapsed ? StopSheetHeaderMetrics.collapsedBottomPadding : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) { Divider() }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            skeletonLine(width: 220, height: nameLineHeight)
            if !isCollapsed {
                HStack(spacing: 8) {
                    skeletonLine(width: 96, height: subtitleLineHeight)
                    skeletonLine(width: 130, height: subtitleLineHeight)
                }
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { _ in
                        skeletonLine(width: 34, height: subtitleLineHeight)
                    }
                }
            }
        }
        // Pulses so the header reads as actively loading, not stalled. Static under Reduce
        // Motion, per the global constraints.
        .opacity(reduceMotion ? 1 : (pulsing ? 0.4 : 1))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true) // decorative; the loading row below announces progress
    }

    private func skeletonLine(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(uiColor: .secondarySystemFill))
            .frame(width: width, height: height)
    }
}
