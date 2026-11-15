//
//  HomeNearbyDepartureRow.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import CoreLocation
import OBAKitCore

/// A departure in the home sheet's Nearby section: the route, where it's going
/// and how soon, over the stop it leaves from and the walk there.
struct HomeNearbyDepartureRow: View {
    let departure: HomeNearbyDeparture
    /// The rider's location, for the walk time. `nil` leaves it out.
    let userLocation: CLLocation?
    let onSelect: () -> Void

    @Environment(\.obaFormatters) private var formatters
    @Environment(\.dynamicTypeSize) private var typeSize

    private var arrivalDeparture: ArrivalDeparture { departure.arrivalDeparture }
    private var status: DepartureStatus { DepartureStatus(arrivalDeparture: arrivalDeparture) }

    private var headsign: String {
        arrivalDeparture.tripHeadsign ?? arrivalDeparture.routeAndHeadsign
    }

    /// A walk longer than this isn't one: the map has been moved away from
    /// the rider, and "190 min walk" under every row would be noise.
    static let longestWalkMinutes = 60

    /// "5 min walk", as the stop page this row opens says it, so the two agree:
    /// the same estimate, and nothing at all for a rider standing at the stop.
    private var walkTime: String? {
        guard let info = WalkTimeInfo.compute(
            from: userLocation,
            to: departure.stop.location,
            speedMetersPerSecond: WalkingSpeed.defaultMetersPerSecond
        ), info.walkMinutes <= Self.longestWalkMinutes else { return nil }
        return StopDirectionsPill.walk.text(for: info)
    }

    /// The stop, then the walk to it: "California & Myrtle · 5 min walk".
    private var subtitle: String {
        [departure.stop.name, walkTime].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 12) {
                RouteBadgeView(
                    routeShortName: arrivalDeparture.routeShortName,
                    routeColor: Color(uiColor: arrivalDeparture.route.color ?? ThemeColors.shared.brand),
                    size: 36
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(headsign)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.primary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    if typeSize.isAccessibilitySize {
                        countdown
                    }
                }
                Spacer(minLength: 8)
                if !typeSize.isAccessibilitySize {
                    countdown
                        .fixedSize()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(formatters.accessibilityValue(for: arrivalDeparture))
        .accessibilityAddTraits([.isButton, .updatesFrequently])
    }

    private var countdown: some View {
        CountdownView(
            minutes: max(0, arrivalDeparture.arrivalDepartureMinutes),
            isRealTime: status.isRealTime,
            color: Color(uiColor: status.color),
            emphasized: false
        )
    }

    /// The route and headsign as the stop page speaks them, then the stop and
    /// the walk, which the drawn subtitle carries.
    private var accessibilityLabelText: String {
        [formatters.accessibilityLabel(for: arrivalDeparture), departure.stop.name, walkTime]
            .compactMap { $0 }
            .formatted(.list(type: .and, width: .narrow))
    }
}
