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

    /// Set by the host so the alarm and Live Activity buttons render their
    /// current state rather than always offering to start something.
    var hasAlarm = false
    var isTrackingLiveActivity = false

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
            TripPageBackRow(title: originTitle, onBack: actions.onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    card

                    let rows = stopList.rows
                    if !rows.isEmpty {
                        Text(stopCountTitle(rows.count))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.leading, 4)

                        TripStopListView(
                            rows: rows,
                            routeColor: routeColor,
                            routeType: route?.routeType ?? .unknown,
                            onSelect: { row in actions.onSelectStop(stopID(for: row)) }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TripActionBar(
                canStartLiveActivity: actions.canStartLiveActivity,
                isTrackingLiveActivity: isTrackingLiveActivity,
                canSchedule: actions.canSchedule,
                canAlarm: actions.canAlarm,
                hasAlarm: hasAlarm,
                onLiveActivity: actions.onLiveActivity,
                onBookmark: actions.onBookmark,
                onSchedule: actions.onSchedule,
                onAlarm: actions.onAlarm
            )
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

    private func stopCountTitle(_ count: Int) -> String {
        String(
            format: OBALoc("trip_page.all_stops_fmt", value: "All %d stops", comment: "Header above the trip's full stop list. %d is the number of stops. Plural forms live in Localizable.stringsdict; this value is only the not-found fallback."),
            count
        )
    }

    /// Row ids are position-qualified (`"3-1_75403"`) so a loop route's repeat
    /// visits stay distinct; the stop ID is everything after the first hyphen.
    private func stopID(for row: TripStopListModel.Row) -> StopID {
        String(row.id.drop(while: { $0 != "-" }).dropFirst())
    }
}

/// The back affordance. A circular button beside the originating screen's name,
/// rather than a navigation bar: the page is pushed into a sheet whose root has
/// no bar, and adding one would impose a top safe area that eats the sheet's
/// scarce height.
private struct TripPageBackRow: View {
    let title: String?
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.backward")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .background(Color(uiColor: .tertiarySystemFill), in: Circle())
            }
            .tint(Color(uiColor: .label))
            .accessibilityLabel(Strings.back)

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
