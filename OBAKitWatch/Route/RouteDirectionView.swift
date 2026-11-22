//
//  RouteDirectionView.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import MapKit
import OBAKitCore

/// Where to catch one route heading one way, and when: the nearest stop's next
/// three departures, then up to two other nearby stops' next departure.
struct RouteDirectionView: View {
    let model: RouteDirectionModel
    @Environment(WatchAppHost.self) private var host
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    /// Departures listed for the nearest stop; later ones are noise on a watch.
    private let departureLimit = 3

    var body: some View {
        List {
            Section {
                header
            }

            if let nearest = model.stops.first {
                Section {
                    ForEach(nearest.departures.prefix(departureLimit)) { departure in
                        DepartureRow(departure: departure, route: model.direction.route, headsign: model.direction.headsign, formatters: host.formatters)
                    }
                } header: {
                    stopHeader(nearest)
                }
            } else {
                Section {
                    Text(OBALoc("arrivals.empty", value: "No departures in the next 60 minutes.", comment: "Empty state"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    stopHeader(model.direction.nearestStop)
                }
            }

            let others = model.stops.dropFirst()
            if !others.isEmpty {
                Section {
                    ForEach(others) { other in
                        NavigationLink(value: other.stop) {
                            AlsoNearbyRow(stop: other, formatters: host.formatters)
                        }
                    }
                } header: {
                    Text(OBALoc("route.also_nearby", value: "Also nearby", comment: "Section header: other nearby stops served by the same route and direction"))
                }
            }

            Section {
                NavigationLink(value: (model.stops.first ?? model.direction.nearestStop).stop) {
                    Text(OBALoc("route.all_arrivals", value: "All arrivals at this stop", comment: "Opens every route's departures at the nearest stop"))
                        .font(.footnote)
                }
            } footer: {
                Text(String(
                    format: OBALoc("arrivals.updated_at_fmt", value: "Updated at %@", comment: "%@ is a short time, e.g. 3:42 PM"),
                    host.formatters.timeFormatter.string(from: model.updatedAt)
                ))
                .font(.caption2)
                .foregroundStyle(model.stale ? .orange : .secondary)
            }
        }
        .toolbar {
            if model.opposite != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.switchDirection()
                    } label: {
                        Label(OBALoc("route.switch_direction", value: "Switch direction", comment: "Button: show the same route heading the other way"), systemImage: "arrow.left.arrow.right")
                    }
                }
            }
        }
        .onAppear {
            isVisible = true
            model.startPolling()
        }
        .onDisappear {
            isVisible = false
            model.stopPolling()
        }
        .onChange(of: scenePhase) { _, phase in
            // A wrist raise makes every view in the stack active again, including
            // this one when a pushed screen is covering it. Only the one on
            // screen should poll.
            if phase == .active {
                if isVisible { model.startPolling() }
            } else {
                model.stopPolling()
            }
        }
        .onChange(of: host.currentRegion) { _, _ in
            if isVisible && scenePhase == .active {
                model.stopPolling()
                model.startPolling()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            RouteDirectionBadge(route: model.direction.route)
            Text(model.direction.headsign)
                .font(.headline)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RouteDirectionBadge.accessibilityLabel(route: model.direction.route, headsign: model.direction.headsign))
        .accessibilityAddTraits(.isHeader)
    }

    private func stopHeader(_ stop: RouteDirectionStop) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(stop.stop.nameWithLocalizedDirectionAbbreviation)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(host.formatters.distanceFormatter.string(fromDistance: stop.distance))
                .font(.caption2)
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}

/// One departure at the nearest stop: countdown, clock time, and adherence.
private struct DepartureRow: View {
    let departure: ArrivalDeparture
    let route: Route
    let headsign: String
    let formatters: Formatters

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var statusColor: Color {
        Color(uiColor: formatters.colorForScheduleStatus(departure.scheduleStatus))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                // A single-child stack lays out exactly as the bare countdown, so
                // the row is unchanged unless the glyph is drawn.
                HStack(spacing: 2) {
                    // Schedule-only countdowns already carry a clock glyph.
                    if differentiateWithoutColor, departure.predicted {
                        Image(systemName: departure.scheduleStatus.differentiateWithoutColorGlyphName(isRealTime: true))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(statusColor)
                            .accessibilityHidden(true)
                    }
                    CountdownView(departure: departure.arrivalDepartureDate, isRealTime: departure.predicted, color: statusColor)
                }
                Spacer(minLength: 4)
                Text(formatters.timeFormatter.string(from: departure.arrivalDepartureDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(formatters.deviationLabel(for: departure))
                .font(.caption2)
                .foregroundStyle(statusColor)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(
                format: OBALoc("arrivals.row.a11y_fmt", value: "%1$@ to %2$@, %3$@", comment: "VoiceOver: route, headsign, time until departure"),
                route.shortName, headsign, formatters.formattedTime(until: departure)
            )
        )
        .accessibilityValue(formatters.deviationLabel(for: departure))
    }
}

/// Another stop for the same direction: where it is and its next departure.
private struct AlsoNearbyRow: View {
    let stop: RouteDirectionStop
    let formatters: Formatters

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        let next = stop.departures[0]
        let countdownColor = Color(uiColor: formatters.colorForScheduleStatus(next.scheduleStatus))
        VStack(alignment: .leading, spacing: 2) {
            Text(stop.stop.nameWithLocalizedDirectionAbbreviation)
                .font(.footnote)
                .lineLimit(2)
            HStack(alignment: .firstTextBaseline) {
                Text(formatters.distanceFormatter.string(fromDistance: stop.distance))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                // A single-child stack lays out exactly as the bare countdown, so
                // the row is unchanged unless the glyph is drawn.
                HStack(spacing: 2) {
                    // Schedule-only countdowns already carry a clock glyph.
                    if differentiateWithoutColor, next.predicted {
                        Image(systemName: next.scheduleStatus.differentiateWithoutColorGlyphName(isRealTime: true))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(countdownColor)
                            .accessibilityHidden(true)
                    }
                    CountdownView(
                        departure: next.arrivalDepartureDate,
                        isRealTime: next.predicted,
                        color: countdownColor,
                        emphasized: false
                    )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stop.stop.nameWithLocalizedDirectionAbbreviation)
        .accessibilityValue(formatters.formattedTime(until: next))
    }
}
