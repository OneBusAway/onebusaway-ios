//
//  TripStopRow.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A row displaying a single stop in the trip timeline
struct TripStopRow: View {
    let stopTime: TripStopTime
    let isUserDestination: Bool
    let isCurrentVehicleLocation: Bool
    let routeType: Route.RouteType
    let formatters: Formatters
    var isFirst: Bool = false
    var isLast: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 0) {
                // Timeline segment indicator
                SimpleTripSegmentIndicator(
                    isUserDestination: isUserDestination,
                    isCurrentVehicleLocation: isCurrentVehicleLocation,
                    routeType: routeType,
                    isFirst: isFirst,
                    isLast: isLast
                )
                .frame(width: 44)

                // Stop info
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stopTime.stop.name)
                            .font(.body)
                            .foregroundStyle(isUserDestination ? Color.accentColor : .primary)
                            .lineLimit(2)

                        if isCurrentVehicleLocation {
                            Text("Vehicle is here")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Arrival time
                    Text(formattedTime)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                }
                .padding(.vertical, 12)
                .padding(.trailing, 16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var formattedTime: String {
        formatters.timeFormatter.string(from: stopTime.arrivalDate)
    }

    private var accessibilityLabel: String {
        var parts = [stopTime.stop.name, "arrives at \(formattedTime)"]
        if isUserDestination {
            parts.append("your destination")
        }
        if isCurrentVehicleLocation {
            parts.append("vehicle is here")
        }
        return parts.joined(separator: ", ")
    }
}

/// A row for navigating to an adjacent trip (previous or next)
struct AdjacentTripRow: View {
    let trip: Trip
    let order: AdjacentTripOrder
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 12) {
                // Arrow icon
                Image(systemName: order == .previous ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(order == .previous ? "Previous Trip" : "Next Trip")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(tripDescription)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var tripDescription: String {
        if let routeShortName = trip.route?.shortName {
            return "\(routeShortName) - \(trip.routeHeadsign)"
        }
        return trip.routeHeadsign
    }
}

#if DEBUG
struct TripStopRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            // Preview would require mock data
            Text("TripStopRow Preview")
                .font(.headline)
            Text("Requires TripStopTime mock data")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
#endif
