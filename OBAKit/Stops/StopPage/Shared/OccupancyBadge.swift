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

/// Compact occupancy indicator for departure rows in both chronological and
/// grouped modes: a crowding-meter bars glyph plus a short label
/// ("Many seats", "Some seats", …).
///
/// The existing `OccupancyStatusView` is a reuse-oriented UIKit `UIView` whose
/// `configure`/`prepareForReuse` lifecycle doesn't map onto a SwiftUI List row,
/// so rather than wrap it in a `UIViewRepresentable` this is a lightweight
/// text-plus-icon label. Display text uses short `occupancy_status.short.*`
/// strings sized for a one-line row; VoiceOver (via `localizedDescription`)
/// keeps the full `occupancy_status.*` wording shared with
/// `OccupancyStatusView`. Callers gate it on `DepartureStatus.showsOccupancy`
/// (real-time only, §4.1).
struct OccupancyBadge: View {
    let occupancy: ArrivalDeparture.OccupancyStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "cellularbars", variableValue: Self.fillLevel(occupancy))
            Text(Self.shortLabel(occupancy))
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.localizedDescription(occupancy))
    }

    /// How full the vehicle is, as the bars glyph's variable value: more filled
    /// bars = more crowded. `cellularbars` has four segments, so levels are
    /// quarter steps.
    static func fillLevel(_ occupancy: ArrivalDeparture.OccupancyStatus) -> Double {
        switch occupancy {
        case .empty:
            return 0.0
        case .manySeatsAvailable:
            return 0.25
        case .fewSeatsAvailable:
            return 0.5
        case .standingRoomOnly:
            return 0.75
        case .crushedStandingRoomOnly, .full, .notBoardable, .notAcceptingPassengers:
            return 1.0
        case .noDataAvailable, .unknown:
            return 0.0
        }
    }

    /// Short display wording sized for a single row line. Deliberately separate
    /// keys from the full `occupancy_status.*` strings, which stay untouched for
    /// `OccupancyStatusView` and VoiceOver.
    static func shortLabel(_ occupancy: ArrivalDeparture.OccupancyStatus) -> String {
        switch occupancy {
        case .empty:
            return OBALoc("occupancy_status.short.empty", value: "Empty", comment: "Short occupancy label: vehicle is empty")
        case .manySeatsAvailable:
            return OBALoc("occupancy_status.short.many_seats", value: "Many seats", comment: "Short occupancy label: many seats available")
        case .fewSeatsAvailable:
            return OBALoc("occupancy_status.short.some_seats", value: "Some seats", comment: "Short occupancy label: few seats available")
        case .standingRoomOnly:
            return OBALoc("occupancy_status.short.standing_room", value: "Standing room", comment: "Short occupancy label: standing room only")
        case .crushedStandingRoomOnly:
            return OBALoc("occupancy_status.short.crowded", value: "Crowded", comment: "Short occupancy label: crushed standing room only")
        case .full:
            return OBALoc("occupancy_status.short.full", value: "Full", comment: "Short occupancy label: vehicle is full")
        case .notBoardable, .notAcceptingPassengers:
            return OBALoc("occupancy_status.short.not_boarding", value: "Not boarding", comment: "Short occupancy label: vehicle is not accepting passengers")
        case .noDataAvailable, .unknown:
            return OBALoc("occupancy_status.short.unknown", value: "Unknown", comment: "Short occupancy label: occupancy is unknown")
        }
    }

    /// Human-readable occupancy string. Mirrors `OccupancyStatusView`'s mapping,
    /// reusing the identical `occupancy_status.*` keys so both surfaces localize
    /// from the same catalog entries. Used for VoiceOver, where the full wording
    /// is clearer than the short display label.
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
