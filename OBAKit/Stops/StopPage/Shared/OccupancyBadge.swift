//
//  OccupancyBadge.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Compact occupancy indicator for expanded departure rows.
///
/// The existing `OccupancyStatusView` is a reuse-oriented UIKit `UIView` whose
/// `configure`/`prepareForReuse` lifecycle doesn't map onto a SwiftUI List row,
/// so rather than wrap it in a `UIViewRepresentable` this is a lightweight
/// text-plus-icon label that reuses the same `occupancy_status.*` localization
/// keys — translations stay shared. Callers gate it on
/// `DepartureStatus.showsOccupancy` (real-time only, §4.1).
struct OccupancyBadge: View {
    let occupancy: ArrivalDeparture.OccupancyStatus

    var body: some View {
        Label {
            Text(Self.localizedDescription(occupancy))
        } icon: {
            Image(systemName: "person.fill")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Human-readable occupancy string. Mirrors `OccupancyStatusView`'s mapping,
    /// reusing the identical `occupancy_status.*` keys so both surfaces localize
    /// from the same catalog entries.
    static func localizedDescription(_ occupancy: ArrivalDeparture.OccupancyStatus) -> String {
        switch occupancy {
        case .empty:
            return OBALoc("occupancy_status.empty", value: "Empty", comment: "Vehicle occupancy is zero")
        case .manySeatsAvailable:
            return OBALoc("occupancy_status.many_seats_available", value: "Many seats available", comment: "Vehicle occupancy is low")
        case .fewSeatsAvailable:
            return OBALoc("occupancy_status.few_seats_available", value: "Few seats available", comment: "Vehicle occupancy is medium")
        case .standingRoomOnly:
            return OBALoc("occupancy_status.standing_room_only", value: "Standing room only", comment: "Vehicle occupancy is high")
        case .crushedStandingRoomOnly:
            return OBALoc("occupancy_status.crushed_standing_room_only", value: "Crushed standing room only", comment: "Vehicle occupancy is very high")
        case .full:
            return OBALoc("occupancy_status.full", value: "Full", comment: "Vehicle occupancy is full")
        case .notBoardable, .notAcceptingPassengers:
            return OBALoc("occupancy_status.not_accepting_passengers", value: "Not accepting passengers", comment: "Vehicle is not accepting any passengers")
        case .noDataAvailable, .unknown:
            return OBALoc("occupancy_status.unknown", value: "Unknown", comment: "Vehicle occupancy status is unknown.")
        }
    }
}
