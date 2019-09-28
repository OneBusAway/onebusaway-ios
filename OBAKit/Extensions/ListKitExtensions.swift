//
//  ListKitExtensions.swift
//  OBANext
//
//  Created by Aaron Brethorst on 1/13/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit
import IGListKit

public extension ListAdapterDataSource where Self: UIViewController {

    /// Provides a default way to map objects to `ListSectionController` objects.
    ///
    /// - Parameter object: An object that will be mapped to a `ListSectionController`
    /// - Returns: The `ListSectionController`
    func defaultSectionController(for object: Any) -> ListSectionController {
        switch object {
        case is TableSectionData:
            return TableSectionController()
        case is TripStopListItem:
            return TripStopSectionController()
        default:
            return LabelSectionController()
        }
    }
}
