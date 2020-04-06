//
//  AdjacentTripController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 2/14/20.
//

import Foundation
import IGListKit
import OBAKitCore

// MARK: - View Model

enum AdjacentTripOrder {
    case previous, next
}

final class AdjacentTripSection: NSObject, ListDiffable {
    let order: AdjacentTripOrder
    let trip: Trip
    let selected: VoidBlock

    init(trip: Trip, order: AdjacentTripOrder, selected: @escaping VoidBlock) {
        self.trip = trip
        self.order = order
        self.selected = selected
    }

    // MARK: - ListDiffable

    func diffIdentifier() -> NSObjectProtocol {
        return self
    }

    func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let rhs = object as? AdjacentTripSection else {
            return false
        }

        return order == rhs.order && trip == rhs.trip
    }
}

// MARK: - Controller

final class AdjacentTripController: OBAListSectionController<AdjacentTripSection> {

    override func cellForItem(at index: Int) -> UICollectionViewCell {
        guard
            let cell = collectionContext?.dequeueReusableCell(of: TripStopCell.self, for: self, at: index) as? TripStopCell,
            let sectionData = sectionData
        else {
            fatalError()
        }

        let titleFormat: String
        if sectionData.order == .previous {
            titleFormat = OBALoc("trip_details_controller.starts_as_fmt", value: "Starts as %@", comment: "Describes the previous trip of this vehicle. e.g. Starts as 10 - Downtown Seattle")
        }
        else {
            titleFormat = OBALoc("trip_details_controller.continues_as_fmt", value: "Continues as %@", comment: "Describes the next trip of this vehicle. e.g. Continues as 10 - Downtown Seattle")
        }

        cell.titleLabel.text = String(format: titleFormat, sectionData.trip.routeHeadsign)
        cell.tripSegmentView.adjacentTripOrder = sectionData.order

        return cell
    }

    override func didSelectItem(at index: Int) {
        super.didSelectItem(at: index)

        guard let object = sectionData else { return }

        object.selected()
    }
}
