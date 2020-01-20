//
//  ListKitExtensions.swift
//  OBANext
//
//  Created by Aaron Brethorst on 1/13/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit
import IGListKit
import OBAKitCore
import CocoaLumberjackSwift

extension ListAdapterDataSource where Self: AppContext {

    /// Provides a default way to map objects to `ListSectionController` objects.
    ///
    /// - Parameter object: An object that will be mapped to a `ListSectionController`
    /// - Returns: The `ListSectionController`
    func defaultSectionController(for object: Any) -> ListSectionController {
        switch object {
        case is BookmarkSectionData:
            return BookmarkSectionController(formatters: application.formatters)
        case is MessageSectionData:
            return MessageSectionController()
        case is TableSectionData:
            return TableSectionController()
        case is TripStopListItem:
            return TripStopSectionController()
        default:
            DDLogWarn("You are trying to render \(object), which doesn't have a SectionController mapped to it. Is this a mistake?")
            return LabelSectionController()
        }
    }
}
