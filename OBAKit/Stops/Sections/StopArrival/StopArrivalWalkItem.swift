//
//  StopArrivalWalkItem.swift
//  OBAKit
//
//  Created by Alan Chu on 2/24/21.
//

import OBAKitCore
import CoreLocation

struct StopArrivalWalkItem: OBAListViewItem {
    var contentConfiguration: OBAContentConfiguration {
        let config = OBAListRowConfiguration(
            text: "\(distance) meters",
            secondaryText: "\(timeToWalk) seconds",
            appearance: .value,
            accessoryType: .none)
        return config
    }
    var onSelectAction: OBAListViewAction<StopArrivalWalkItem>?

    let id: String
    let distance: CLLocationDistance
    let timeToWalk: TimeInterval

    static func == (lhs: StopArrivalWalkItem, rhs: StopArrivalWalkItem) -> Bool {
        return lhs.id == rhs.id &&
            lhs.distance == rhs.distance &&
            lhs.timeToWalk == rhs.timeToWalk
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
