//
//  StopSection.swift
//  OBANext
//
//  Created by Aaron Brethorst on 12/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import CoreLocation
import UIKit
import IGListKit

// MARK: - View Model

public class StopViewModel: NSObject, ListDiffable {
    let name: String
    let stopID: String
    let direction: String?
    let routeNames: [String]
    let coordinate: CLLocationCoordinate2D
    let image: UIImage?

    convenience init(stop: Stop) {
        let routeNames = stop.routes.map { $0.shortName }
        self.init(name: stop.name, stopID: stop.id, direction: stop.direction, routeNames: routeNames, coordinate: stop.coordinate)
    }

    init(name: String, stopID: String, direction: String?, routeNames: [String], coordinate: CLLocationCoordinate2D, image: UIImage? = nil) {
        self.name = name
        self.stopID = stopID
        self.direction = direction
        self.routeNames = routeNames
        self.coordinate = coordinate
        self.image = image
    }

    // MARK: - Helpers

    var nameWithDirection: String {
        guard let dir = direction else {
            return name
        }

        return "\(name) (\(dir))"
    }

    // MARK: - ListDiffable

    public func diffIdentifier() -> NSObjectProtocol {
        return "stop_\(stopID)" as NSObjectProtocol
    }

    public func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard self !== object else { return true }
        guard let object = object as? StopViewModel else { return false }
        return name == object.name
            && stopID == object.stopID
            && direction == object.direction
            && routeNames == object.routeNames
            && coordinate.latitude == object.coordinate.latitude
            && coordinate.longitude == object.coordinate.longitude
            && image == object.image
    }
}

// MARK: - Section Controller

class StopSectionController: ListSectionController {
    var data: StopViewModel?

    override init() {
        super.init()
        inset = UIEdgeInsets(top: 0, left: 0, bottom: 30, right: 0)
    }

    override func sizeForItem(at index: Int) -> CGSize {
        return CGSize(width: collectionContext!.containerSize.width, height: 55)
    }

    override func cellForItem(at index: Int) -> UICollectionViewCell {
        guard
            let ctx = collectionContext,
            let data = data,
            let cell = ctx.dequeueReusableCell(of: StopCell.self, for: self, at: index) as? StopCell
        else {
            fatalError()
        }
        cell.viewModel = data
        return cell
    }

    override func didUpdate(to object: Any) {
        precondition(object is StopViewModel)
        data = object as? StopViewModel
    }

//    override func didSelectItem(at index: Int) {
//        guard
//            let data = data,
//            let viewController = viewController as? NearbyViewController
//        else {
//            return
//        }
//
//        viewController.selectedStopViewModel(data)
//    }
}


