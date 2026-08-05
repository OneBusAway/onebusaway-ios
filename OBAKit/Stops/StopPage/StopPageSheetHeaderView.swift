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
/// A plain-value view except for `mapFocus` — it never touches `StopViewModel`.
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

    /// Map focus state. This is the one view in the Stop page subtree that
    /// observes it — see `StopPageView`'s note on observation discipline.
    @ObservedObject var mapFocus: StopMapFocus

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var subtitle: String {
        Formatters.formattedCodeAndDirection(stop: stop)
    }

    /// Sorted, de-duplicated route short names for the badge row. Mirrors
    /// `Formatters.formattedRoutes`' filtering (some agencies omit short names).
    ///
    /// Membership and ordering are unchanged from before this feature — `stop.routes`, deduped by
    /// short name, alphabetical, not filtered by `hiddenRoutes` — so the sheet and the pushed stop
    /// page keep showing the same header, and the VoiceOver summary built from `stop.routes` keeps
    /// matching what is drawn.
    private var routeBadgeNames: [String] {
        var seen = Set<String>()
        return stop.routes
            .map(\.shortName)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Every route ID sharing each short name, so a chip whose short name collapses two `RouteID`s
    /// can still resolve a tap to whichever of them the map is actually drawing.
    private var routeIDsByShortName: [String: [RouteID]] {
        Dictionary(grouping: stop.routes, by: \.shortName).mapValues { $0.map(\.id) }
    }

    private var chips: [RouteChip] {
        RouteChip.chips(
            forRouteShortNames: stop.routes.map(\.shortName),
            routeIDsByShortName: routeIDsByShortName
        )
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
                    // The routes-served summary lives here rather than on the chip row below:
                    // that row has to stay reachable chip-by-chip (see `.contain` below), so the
                    // one-element summary VoiceOver used to read there moves onto the header's own
                    // identity element instead.
                    .accessibilityLabel(headerAccessibilityLabel)

                    StopSheetCloseButton(action: onClose)
                }

                if !isCollapsed, walkTime != nil || !chips.isEmpty {
                    // Walk pill and chips share one flowing row, per the design — the pill
                    // leads, a hairline separates it from the routes, and everything wraps
                    // together.
                    //
                    // `FlowLayout` sizes subviews with an unspecified proposal, which a
                    // `Button` answers with a greedy height — that is what once stretched the
                    // walk pill down the whole sheet. So nothing in this row is a `Button`;
                    // the pill and the chips are `Text`-shaped tappable views instead. See
                    // `chipView(_:)`.
                    FlowLayout(hSpacing: 6, vSpacing: 6) {
                        if let walkTime {
                            walkPill(walkTime)
                        }
                        if walkTime != nil, !chips.isEmpty {
                            rowSeparator
                        }
                        ForEach(chips) { chip in
                            chipView(chip)
                        }
                    }
                    // `.contain`, not `.ignore`: each chip carries its own trait and label (and
                    // needs to be individually reachable for `.onTapGesture` to work under
                    // VoiceOver), so the row can no longer collapse to one summary element. The
                    // summary itself moved onto the header's identity label above.
                    .accessibilityElement(children: .contain)
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

    /// The hairline between the walk pill and the route chips. Sized off the same metric the
    /// pill and chips are, so it stays proportional as Dynamic Type grows them.
    private var rowSeparator: some View {
        Capsule()
            .fill(Color(uiColor: .separator))
            .frame(width: 1, height: pillHeight)
            .padding(.horizontal, 3)
            .accessibilityHidden(true)
    }

    /// The walk-time pill: a tinted capsule rather than the dark card's solid green one. The
    /// foreground keeps the full-strength on-time color, which is already tuned per-appearance
    /// for legibility at small sizes (see `ThemeColors.departureOnTime`).
    ///
    /// Deliberately NOT a `Button`, and deliberately the same font and padding as a chip.
    /// `FlowLayout` places its subviews top-anchored, so pill and chips must resolve to the same
    /// height or the row reads as ragged — matching their type ramp is what holds that at every
    /// Dynamic Type size, where a hardcoded height would not.
    private func walkPill(_ info: WalkTimeInfo) -> some View {
        let text = walkPillText(info)
        return HStack(spacing: 4) {
            Image(systemName: "figure.walk")
                .accessibilityHidden(true) // the text below carries the meaning
            // Pinning the text to one unwrappable line makes the pill's width a function of its
            // content. Without it the pill came out 60pt wide and 168pt tall, with "2 min walk"
            // broken one character per line.
            Text(text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(chipFont)
        .foregroundStyle(Color(uiColor: ThemeColors.shared.departureOnTime))
        .padding(.horizontal, chipHorizontalPadding)
        .padding(.vertical, chipVerticalPadding)
        .background(Color(uiColor: ThemeColors.shared.departureOnTime).opacity(0.14), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture(perform: onWalkingDirections)
        // `.accessibilityHidden(true)` on the glyph above was not enough on its
        // own: this view adds a trait but named no element, and the walk glyph
        // surfaced as a second, sibling stop — a 10x16pt target whose whole spoken
        // content was the symbol's stock name, "Walk". Naming the element is what
        // collapses the subtree. `chipView(_:)` below never had the bug because it
        // has always set an explicit `.accessibilityLabel`.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(OBALoc("stop_page.header.walk_a11y_hint", value: "Opens walking directions to this stop.", comment: "VoiceOver hint on the header card's walk-time button."))
    }

    // MARK: - Shared pill metrics

    /// One type ramp for the pill and the chips — see `walkPill(_:)` on why they must match.
    private var chipFont: Font { .footnote.weight(.semibold) }
    private var chipHorizontalPadding: CGFloat { 10 }
    private var chipVerticalPadding: CGFloat { 5 }

    @ScaledMetric(relativeTo: .footnote) private var pillHeight: CGFloat = 20

    @ViewBuilder
    private func chipView(_ chip: RouteChip) -> some View {
        let drawn = chip.drawnRoute(in: mapFocus)
        let isFocused = chip.focusableRouteID(in: mapFocus) == mapFocus.focusedRouteID
            && mapFocus.focusedRouteID != nil
        let isDimmed = mapFocus.focusedRouteID != nil && !isFocused

        HStack(spacing: 5) {
            if let drawn {
                // The route's map-line color, so the chip and its line read as one thing.
                Capsule()
                    .fill(Color(uiColor: drawn.color))
                    .frame(width: 13, height: 4)
            }
            Text(chip.shortName)
                .font(chipFont)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let drawn, drawn.hasLiveVehicle {
                // Only when there is a vehicle on the map to point at. Route-colored, per the
                // design, so the dot pairs with the dash on the other side of the name rather
                // than reading as a second, unrelated status color.
                Circle()
                    .fill(Color(uiColor: drawn.color))
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, chipHorizontalPadding)
        .padding(.vertical, chipVerticalPadding)
        .background(
            Capsule().fill(isFocused
                ? Color(uiColor: drawn?.color ?? .clear).opacity(0.16)
                : Color(uiColor: .secondarySystemFill))
        )
        .overlay(
            Capsule()
                .strokeBorder(isFocused ? Color(uiColor: drawn?.color ?? .clear) : .clear, lineWidth: 1.5)
        )
        .opacity(isDimmed ? 0.45 : 1)
        // NOT a Button: FlowLayout proposes .unspecified, which a Button answers with a greedy
        // height — that is what stretched the walk pill down the whole sheet. See the note above
        // this view.
        .contentShape(Rectangle())
        .onTapGesture { chip.toggleFocus(in: mapFocus) }
        .accessibilityAddTraits(chip.isInteractive(in: mapFocus) ? .isButton : [])
        .accessibilityLabel(chipAccessibilityLabel(for: chip, drawn: drawn, isFocused: isFocused))
    }

    private func chipAccessibilityLabel(
        for chip: RouteChip,
        drawn: StopRouteFocusModel.DrawnRoute?,
        isFocused: Bool
    ) -> String {
        var parts = [chip.shortName]
        if drawn?.hasLiveVehicle == true { parts.append(liveTrackingLabel) }
        if isFocused { parts.append(highlightedLabel) }
        return parts.joined(separator: ", ")
    }

    private var liveTrackingLabel: String {
        OBALoc("stop_header.chip.live_tracking", value: "live tracking",
               comment: "Spoken suffix on a route chip whose route has a vehicle on the map.")
    }

    private var highlightedLabel: String {
        OBALoc("stop_header.chip.highlighted", value: "highlighted on map",
               comment: "Spoken suffix on the currently-focused route chip.")
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

    /// The header identity element's spoken label: name, then (uncollapsed) subtitle and the
    /// routes-served summary that used to live on the chip row. Built explicitly rather than left
    /// to `.accessibilityElement(children: .combine)`'s default combination because
    /// `.accessibilityLabel` below replaces that default outright.
    private var headerAccessibilityLabel: String {
        var parts = [stop.name]
        if !isCollapsed {
            parts.append(subtitle)
            if !chips.isEmpty {
                parts.append(routeListAccessibilityLabel)
            }
        }
        return parts.joined(separator: ", ")
    }
}

/// One header chip. Membership and ordering are unchanged from before this
/// feature — `stop.routes`, deduped by short name, alphabetical — so the sheet
/// and the pushed stop page keep showing the same header for the same stop, and
/// the VoiceOver summary built from `stop.routes` keeps matching what is drawn.
///
/// Carries every route ID sharing its short name, because today's dedupe is by
/// string: two `RouteID`s with short name "40" collapse to one badge, and the tap
/// has to resolve to whichever of them the map is actually drawing.
struct RouteChip: Identifiable, Hashable {
    let shortName: String
    let routeIDs: [RouteID]
    var id: String { shortName }

    static func chips(
        forRouteShortNames shortNames: [String],
        routeIDsByShortName: [String: [RouteID]]
    ) -> [RouteChip] {
        let unique = Set(shortNames.filter { !$0.isEmpty })
        return unique
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { RouteChip(shortName: $0, routeIDs: routeIDsByShortName[$0] ?? []) }
    }

    /// The route this chip's tap should act on: the first of its IDs the map drew
    /// with a live vehicle.
    func focusableRouteID(in focus: StopMapFocus) -> RouteID? {
        routeIDs.first { focus.isFocusable(routeID: $0) }
    }

    func isInteractive(in focus: StopMapFocus) -> Bool {
        focusableRouteID(in: focus) != nil
    }

    func drawnRoute(in focus: StopMapFocus) -> StopRouteFocusModel.DrawnRoute? {
        routeIDs.lazy.compactMap { focus.drawnRoute(for: $0) }.first
    }

    func toggleFocus(in focus: StopMapFocus) {
        guard let routeID = focusableRouteID(in: focus) else { return }
        focus.toggleFocus(routeID: routeID)
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
