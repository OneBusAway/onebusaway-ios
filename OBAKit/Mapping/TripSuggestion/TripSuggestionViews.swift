//
//  TripSuggestionViews.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import SwiftUI
import OBAKitCore

// MARK: - Copy

/// The words for the suggestion card and the Choose a Bus sheet.
///
/// "Bus" whenever every vehicle in the suggestion is a bus, "vehicle" otherwise, so
/// a bus and a streetcar together aren't called two buses.
enum TripSuggestionCopy {
    static func allBuses(_ candidates: [TripSuggestionCandidate]) -> Bool {
        candidates.allSatisfy { $0.routeType == .bus }
    }

    static func title(for candidates: [TripSuggestionCandidate]) -> String {
        if candidates.count == 1, let candidate = candidates.first {
            // A bus route is a number; a rail line's short name is already a name
            // ("1 Line"), and "Route 1 Line" reads badly.
            guard candidate.routeType == .bus else {
                return String(format: OBALoc(
                    "trip_suggestion.title_one_line_fmt",
                    value: "On the %@?",
                    comment: "Title of the map card that asks whether the rider is on a particular non-bus line, such as light rail. %@ is the line's short name, e.g. 'On the 1 Line?'"
                ), candidate.routeShortName)
            }
            return String(format: OBALoc(
                "trip_suggestion.title_one_fmt",
                value: "On Route %@?",
                comment: "Title of the map card that asks whether the rider is on a particular bus route. %@ is the route's short name, e.g. 'On Route 10?'"
            ), candidate.routeShortName)
        }
        return allBuses(candidates)
            ? OBALoc("trip_suggestion.title_several_buses", value: "On a bus?", comment: "Title of the map card shown when the rider seems to be on one of several buses moving with them.")
            : OBALoc("trip_suggestion.title_several_vehicles", value: "On a vehicle?", comment: "Title of the map card shown when the rider seems to be on one of several transit vehicles of different kinds (e.g. a bus and a streetcar) moving with them.")
    }

    static func destination(_ headsign: String) -> String {
        String(format: OBALoc(
            "trip_suggestion.destination_fmt",
            value: "To %@",
            comment: "Subtitle naming where the suggested trip goes. %@ is the trip's headsign, e.g. 'To Capitol Hill'."
        ), headsign)
    }

    static let trackTrip = OBALoc("trip_suggestion.track_trip", value: "Track Trip", comment: "Button on the trip suggestion card that opens the suggested trip.")

    static func chooseButton(for candidates: [TripSuggestionCandidate]) -> String {
        allBuses(candidates)
            ? OBALoc("trip_suggestion.choose_bus", value: "Choose Bus", comment: "Button on the trip suggestion card that lists the buses the rider might be on.")
            : OBALoc("trip_suggestion.choose_vehicle", value: "Choose Vehicle", comment: "Button on the trip suggestion card that lists the vehicles, of more than one kind, the rider might be on.")
    }

    static func chooseTitle(for candidates: [TripSuggestionCandidate]) -> String {
        allBuses(candidates)
            ? OBALoc("trip_suggestion.choose_title_bus", value: "Choose a Bus", comment: "Title of the sheet listing the buses the rider might be on.")
            : OBALoc("trip_suggestion.choose_title_vehicle", value: "Choose a Vehicle", comment: "Title of the sheet listing the transit vehicles, of more than one kind, the rider might be on.")
    }

    static func routeAndDestination(_ candidate: TripSuggestionCandidate) -> String {
        guard let headsign = candidate.headsign, !headsign.isEmpty else {
            return String(format: OBALoc("trip_suggestion.route_fmt", value: "Route %@", comment: "A route in the Choose a Bus list when its trip has no headsign. %@ is the route's short name."), candidate.routeShortName)
        }
        return String(format: OBALoc(
            "trip_suggestion.route_destination_fmt",
            value: "Route %1$@ to %2$@",
            comment: "A route in the Choose a Bus list. %1$@ is the route's short name, %2$@ the trip's headsign, e.g. 'Route 10 to Capitol Hill'."
        ), candidate.routeShortName, headsign)
    }

    static func vehicle(_ candidate: TripSuggestionCandidate) -> String? {
        guard let vehicleID = candidate.vehicleID, !vehicleID.isEmpty else { return nil }
        let number = displayVehicleNumber(vehicleID)
        return candidate.routeType == .bus
            ? String(format: OBALoc("trip_suggestion.bus_number_fmt", value: "Bus %@", comment: "A bus's fleet number in the Choose a Bus list, e.g. 'Bus 4521'."), number)
            : String(format: OBALoc("trip_suggestion.vehicle_number_fmt", value: "Vehicle %@", comment: "A non-bus transit vehicle's fleet number in the Choose a Vehicle list, e.g. 'Vehicle 112'."), number)
    }

    /// OBA vehicle IDs carry the agency prefix (`1_4521`); riders know the number.
    static func displayVehicleNumber(_ vehicleID: String) -> String {
        guard let separator = vehicleID.firstIndex(of: "_") else { return vehicleID }
        let number = vehicleID[vehicleID.index(after: separator)...]
        return number.isEmpty ? vehicleID : String(number)
    }
}

// MARK: - Card

/// The card that floats above the home sheet while the rider seems to be on a
/// vehicle: one vehicle offers its trip, several open Choose a Bus.
struct TripSuggestionCard: View {
    let candidates: [TripSuggestionCandidate]
    let onTrack: (TripSuggestionCandidate) -> Void
    let onChoose: () -> Void
    let onDismiss: () -> Void

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 40

    private var single: TripSuggestionCandidate? { candidates.count == 1 ? candidates.first : nil }

    var body: some View {
        // Text on top, buttons below: one row truncated the destination, which is
        // the part that tells the rider whether this is their trip.
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                icon
                titles
            }
            // Side by side at equal widths when they fit, stacked at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons }
                VStack(spacing: 8) { buttons }
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .lineLimit(1)
        }
        .padding(14)
        // Opaque rather than glass: over a busy map, glass left the text too faint.
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(TripSuggestionCopy.title(for: candidates))
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
            if let headsign = single?.headsign, !headsign.isEmpty {
                Text(TripSuggestionCopy.destination(headsign))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var icon: some View {
        Image(systemName: TripSuggestionCopy.allBuses(candidates) ? "bus.fill" : "tram.fill")
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: iconSize, height: iconSize)
            .background(Color(uiColor: ThemeColors.shared.brandAccent), in: Circle())
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var buttons: some View {
        Button {
            if let single { onTrack(single) } else { onChoose() }
        } label: {
            Text(single == nil ? TripSuggestionCopy.chooseButton(for: candidates) : TripSuggestionCopy.trackTrip)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(uiColor: ThemeColors.shared.brandAccent))

        Button(action: onDismiss) {
            Text(Strings.dismiss)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.primary)
    }
}

// MARK: - Choose a Bus

/// The vehicles the rider might be on, closest first. Picking one opens its trip;
/// the Close button backs out.
struct ChooseTripSuggestionView: View {
    let candidates: [TripSuggestionCandidate]
    let formatters: Formatters
    let onSelect: (TripSuggestionCandidate) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List(candidates) { candidate in
                Button {
                    onSelect(candidate)
                } label: {
                    row(candidate)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.insetGrouped)
            .navigationTitle(TripSuggestionCopy.chooseTitle(for: candidates))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SheetDismissButton(.close, action: onClose)
                }
            }
        }
    }

    private func row(_ candidate: TripSuggestionCandidate) -> some View {
        HStack(spacing: 12) {
            RouteBadgeView(
                routeShortName: candidate.routeShortName,
                routeColor: Color(uiColor: candidate.routeColor ?? ThemeColors.shared.brand),
                routeTextColor: candidate.routeTextColor.map { Color(uiColor: $0) },
                size: 40
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(TripSuggestionCopy.routeAndDestination(candidate))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(details(candidate))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// "Bus 4521 · 30 m away · Metro Transit"
    private func details(_ candidate: TripSuggestionCandidate) -> String {
        let distance = String(
            format: OBALoc("trip_suggestion.distance_fmt", value: "%@ away", comment: "How far the rider is from a vehicle in the Choose a Bus list. %@ is a distance, e.g. '30 m away'."),
            formatters.distanceFormatter.string(fromDistance: candidate.distance)
        )
        return [TripSuggestionCopy.vehicle(candidate), distance, candidate.agencyName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

// MARK: - Panel overlay

/// The card's place on the map panel: shown while the controller has a suggestion,
/// and telling the controller when the map is uncovered enough for one.
struct TripSuggestionOverlay: View {
    @ObservedObject var controller: TripSuggestionController
    /// The map is in the foreground with only the home sheet over it.
    let isActive: Bool
    let onTrack: (TripSuggestionCandidate) -> Void
    let onChoose: ([TripSuggestionCandidate]) -> Void
    /// The card's height, or zero when hidden, so the map controls can sit above it.
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        ZStack {
            if !controller.suggestion.isEmpty {
                TripSuggestionCard(
                    candidates: controller.suggestion,
                    onTrack: onTrack,
                    onChoose: { onChoose(controller.suggestion) },
                    onDismiss: { controller.dismiss() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: controller.suggestion)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { _, height in
            onHeightChange(height)
        }
        .onChange(of: isActive, initial: true) { _, active in
            controller.setActive(active)
        }
    }
}

// MARK: - Previews

#if DEBUG
private extension TripSuggestionCandidate {
    static func preview(_ vehicleID: String, route: String, headsign: String, distance: CLLocationDistance, type: Route.RouteType = .bus) -> Self {
        TripSuggestionCandidate(
            id: vehicleID, tripID: "trip_\(vehicleID)", vehicleID: vehicleID, routeShortName: route, headsign: headsign,
            routeType: type, agencyName: "Metro Transit", routeColor: nil, routeTextColor: nil, serviceDate: nil,
            sighting: VehicleSighting(coordinate: CLLocationCoordinate2D(latitude: 47.61, longitude: -122.34), fixTime: Date(), heading: nil),
            distance: distance,
            arrivalDeparture: nil
        )
    }
}

#Preview("Card: one bus") {
    TripSuggestionCard(
        candidates: [.preview("1_4521", route: "10", headsign: "Capitol Hill", distance: 30)],
        onTrack: { _ in }, onChoose: {}, onDismiss: {}
    )
    .padding()
    .background(Color(red: 0.95, green: 0.93, blue: 0.89))
}

#Preview("Card: two buses") {
    TripSuggestionCard(
        candidates: [
            .preview("1_4521", route: "10", headsign: "Capitol Hill", distance: 30),
            .preview("1_3807", route: "12", headsign: "Interbay", distance: 60)
        ],
        onTrack: { _ in }, onChoose: {}, onDismiss: {}
    )
    .padding()
    .background(Color(red: 0.95, green: 0.93, blue: 0.89))
}

#Preview("Choose a Bus") {
    ChooseTripSuggestionView(
        candidates: [
            .preview("1_4521", route: "10", headsign: "Capitol Hill", distance: 30),
            .preview("1_3807", route: "12", headsign: "Interbay", distance: 60)
        ],
        formatters: Formatters(locale: .current, calendar: .current, themeColors: ThemeColors.shared),
        onSelect: { _ in }, onClose: {}
    )
}
#endif
