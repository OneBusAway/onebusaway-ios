//
//  AdjacentTripController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

// MARK: - View Model

enum AdjacentTripOrder {
    case previous, next
}

struct AdjacentTripRowConfiguration: OBAContentConfiguration {
    var order: AdjacentTripOrder
    var routeHeadsign: String

    var formatters: Formatters?

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return TripStopCell.self
    }
}

struct AdjacentTripItem: OBAListViewItem {
    var id: String { trip.id }

    let order: AdjacentTripOrder
    let trip: Trip
    var onSelectAction: OBAListViewAction<AdjacentTripItem>?

    var configuration: OBAListViewItemConfiguration {
        return .custom(AdjacentTripRowConfiguration(order: order, routeHeadsign: trip.routeHeadsign))
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(order)
        hasher.combine(trip)
    }

    static func == (lhs: AdjacentTripItem, rhs: AdjacentTripItem) -> Bool {
        return lhs.order == rhs.order &&
            lhs.trip == rhs.trip
    }
}
