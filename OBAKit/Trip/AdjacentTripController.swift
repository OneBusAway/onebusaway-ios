//
//  AdjacentTripController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import IGListKit
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
    let order: AdjacentTripOrder
    let trip: Trip
    var onSelectAction: OBAListViewAction<AdjacentTripItem>?

    var contentConfiguration: OBAContentConfiguration {
        return AdjacentTripRowConfiguration(order: order, routeHeadsign: trip.routeHeadsign)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(trip.id)
    }

    static func == (lhs: AdjacentTripItem, rhs: AdjacentTripItem) -> Bool {
        return lhs.order == rhs.order &&
            lhs.trip == rhs.trip
    }
}
