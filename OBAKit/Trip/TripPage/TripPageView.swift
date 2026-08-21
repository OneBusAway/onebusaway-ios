//
//  TripPageView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Everything the page can do that needs `Application` — navigation, alarms,
/// bookmarks, Live Activities. Bundled so the view takes one dependency instead
/// of nine closures, and so the hosting controller owns every UIKit reach.
@MainActor
struct TripPageActions {
    var canSchedule = false
    var canAlarm = false
    var canStartLiveActivity = false
    var onBack: () -> Void = {}
    var onSelectStop: (StopID) -> Void = { _ in }
    var onLiveActivity: () -> Void = {}
    var onBookmark: () -> Void = {}
    var onSchedule: () -> Void = {}
    var onAlarm: () -> Void = {}
}

/// The trip page: which vehicle, when it gets to you, and every stop on its way.
///
/// Draws no map. Whatever is showing the map — the stop sheet's, or the
/// standalone host's — is told what to focus through `TripMapFocus`, which is
/// what lets this one view serve both. See `TripPageViewController`.
struct TripPageView: View {
    @ObservedObject var viewModel: TripViewModel

    /// The name of the screen this was pushed from, shown beside the back
    /// button. `nil` where there isn't one to name — a trip opened from vehicle
    /// search, say — in which case the row shows the button alone.
    let originTitle: String?
    let actions: TripPageActions

    /// Which way out the back row offers. Set by the host, which is the only
    /// thing that knows whether this page was pushed or presented.
    var backBehavior: TripPageBackBehavior = .pop

    /// Set by the host so the alarm and Live Activity buttons render their
    /// current state rather than always offering to start something.
    var hasAlarm = false
    var isTrackingLiveActivity = false

    /// `true` while the sheet showing this page sits at its `.tip` detent, where the only thing
    /// that fits is the back row.
    ///
    /// The action bar is pinned as a bottom `safeAreaInset`, and at `.tip` it is taller than the
    /// whole detent — so SwiftUI squeezes the back row and the list to nothing and the sheet peeks
    /// as a Live Activity button floating over the map, with no indication of which trip it
    /// belongs to. Dropping the bar at this detent leaves the row that names the trip's origin,
    /// which is what a peek is for. Mirrors `StopPageView.isCollapsed`.
    var isCollapsed = false

    /// The page's laid-out height, which is the sheet detent's — not the screen's. Feeds the
    /// action bar's ceiling at accessibility sizes; see `TripActionBar.maxHeight`.
    @State private var pageHeight: CGFloat = 0

    /// The largest share of the page the pinned action bar may take before it starts scrolling.
    ///
    /// `pageHeight` is the whole page, so the list gets what's left after both the bar *and* the
    /// fixed back row — not `1 - share`. At 0.45 that arithmetic turns against the list on the
    /// short detent: on the ~330 pt `.half` the bar could take 149 pt against the list's 133 pt.
    /// 0.4 keeps the list ahead there (132 vs 150) and everywhere larger.
    private static let actionBarHeightShare: CGFloat = 0.4

    private var convertible: TripConvertible { viewModel.tripConvertible }
    private var departure: ArrivalDeparture? { convertible.arrivalDeparture }
    private var route: Route? { convertible.trip.route }

    private var routeColor: Color {
        Color(uiColor: route?.color ?? ThemeColors.shared.brand)
    }

    private var stopList: TripStopListModel {
        TripStopListModel.make(
            stopTimes: viewModel.tripDetails?.stopTimes ?? [],
            userStopID: departure?.stopID,
            userStopSequence: departure?.stopSequence,
            closestStopID: convertible.tripStatus?.closestStopID
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TripPageBackRow(title: originTitle, behavior: backBehavior, onBack: actions.onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    card

                    let rows = stopList.rows
                    if !rows.isEmpty {
                        sectionHeader(stopCountTitle(rows.count))

                        TripStopListView(
                            rows: rows,
                            routeColor: routeColor,
                            routeType: route?.routeType ?? .unknown,
                            onSelect: { actions.onSelectStop($0.stopID) }
                        )
                    } else {
                        // Never render the absence as blank space. The stop list is
                        // most of this page, and a silent gap where it should be
                        // reads as a broken screen rather than one still working.
                        sectionHeader(stopsSectionPlaceholderTitle)

                        Text(stopsUnavailableMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        // On the VStack, NOT on the ScrollView inside it. Inset here shortens the
        // scroll view to the bar's top edge, so the list ends above the bar and no
        // row can ever slide under it.
        //
        // Moving it to the ScrollView — the arrangement that would let rows pass
        // beneath the bar — was measured on device to strand the last stops
        // underneath it with no way to scroll them clear. The mechanism is not
        // understood: `StopPageView` puts `safeAreaInset(edge: .bottom)` directly
        // on its `List`, which is the scroll view this same FloatingPanel tracks,
        // and there the inset is honoured. So it is not simply that the panel
        // discards the reservation. Until someone can explain the difference,
        // this stays where it is empirically correct.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isCollapsed {
                TripActionBar(
                    canStartLiveActivity: actions.canStartLiveActivity,
                    isTrackingLiveActivity: isTrackingLiveActivity,
                    canSchedule: actions.canSchedule,
                    canAlarm: actions.canAlarm,
                    hasAlarm: hasAlarm,
                    maxHeight: pageHeight > 0 ? pageHeight * Self.actionBarHeightShare : nil,
                    onLiveActivity: actions.onLiveActivity,
                    onBookmark: actions.onBookmark,
                    onSchedule: actions.onSchedule,
                    onAlarm: actions.onAlarm
                )
            }
        }
        // The page's height is imposed by the host (the sheet detent), not derived from this
        // content, so feeding it back in to bound the bar converges instead of looping.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            pageHeight = newHeight
        }
    }

    private var card: some View {
        TripCardView(
            departure: departure,
            routeShortName: route?.shortName ?? "",
            headsign: departure?.tripHeadsign ?? convertible.trip.headsign ?? route?.shortName ?? "",
            routeColor: routeColor,
            routeTextColor: route?.textColor.map { Color(uiColor: $0) },
            provenance: TripProvenanceLine.text(
                routeName: route?.longName,
                vehicleLabel: vehicleLabel,
                freshness: freshness
            )
        )
    }

    private var vehicleLabel: String? {
        convertible.tripStatus?.vehicleID.map {
            String(format: OBALoc("trip_page.vehicle_label_fmt", value: "Vehicle %@", comment: "Identifies a vehicle by its ID on the trip page, e.g. 'Vehicle 6821'."), $0)
        }
    }

    private var freshness: String? {
        guard let lastUpdate = convertible.tripStatus?.lastUpdate else { return nil }
        return String(
            format: OBALoc("trip_page.position_updated_fmt", value: "position updated %@", comment: "How stale the vehicle's reported position is. %@ is a relative time like '12s ago'."),
            Self.updatedFormatter.localizedString(for: lastUpdate, relativeTo: Date())
        )
    }

    /// Abbreviated ("12s ago"), matching the map callout's freshness line.
    /// Static because these are stateless and rebuilding one per render is
    /// measurably wasteful.
    private static let updatedFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.leading, 4)
    }

    private var stopsSectionPlaceholderTitle: String {
        OBALoc("trip_page.stops_header", value: "Stops", comment: "Header above the trip's stop list before the stops are known.")
    }

    /// Deliberately distinguishes "still loading" from "we asked and got nothing":
    /// the second is a real answer and the rider shouldn't sit waiting on it.
    private var stopsUnavailableMessage: String {
        if viewModel.isLoading {
            return OBALoc("trip_page.stops_loading", value: "Loading this trip's stops…", comment: "Shown while the trip's stop list is being fetched.")
        }
        return OBALoc("trip_page.stops_unavailable", value: "This trip's stop list isn't available right now.", comment: "Shown when the trip's stop list could not be loaded.")
    }

    private func stopCountTitle(_ count: Int) -> String {
        String(
            format: OBALoc("trip_page.all_stops_fmt", value: "All %d stops", comment: "Header above the trip's full stop list. %d is the number of stops. Plural forms live in Localizable.stringsdict; this value is only the not-found fallback."),
            count
        )
    }
}

/// The back affordance. A circular button beside the originating screen's name,
/// rather than a navigation bar: the page is pushed into a sheet whose root has
/// no bar, and adding one would impose a top safe area that eats the sheet's
/// scarce height.
private struct TripPageBackRow: View {
    let title: String?
    /// Drives the glyph and the VoiceOver label together — the two must never
    /// disagree about whether this goes back or closes.
    let behavior: TripPageBackBehavior
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: behavior.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .background(Color(uiColor: .tertiarySystemFill), in: Circle())
            }
            .tint(Color(uiColor: .label))
            .accessibilityLabel(behavior == .pop ? Strings.back : Strings.close)

            if let title {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
