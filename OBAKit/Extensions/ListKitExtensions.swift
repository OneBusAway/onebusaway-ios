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

protocol HasTableStyle: NSObjectProtocol {
    var tableStyle: TableCollectionStyle { get }
}

extension ListAdapterDataSource where Self: AppContext {

    private var styleForCollection: TableCollectionStyle {
        guard let tableStyled = self as? HasTableStyle else {
            return .plain
        }

        return tableStyled.tableStyle
    }

    /// Provides a default way to map objects to `ListSectionController` objects.
    ///
    /// Add new section controller types here.
    ///
    /// - Parameter object: An object that will be mapped to a `ListSectionController`
    /// - Returns: The `ListSectionController`
    func defaultSectionController(for object: Any) -> ListSectionController {
        switch object {
        case is AdjacentTripSection:
            return AdjacentTripController(formatters: application.formatters, style: styleForCollection)
        case is ArrivalDepartureSectionData:
            return StopArrivalSectionController(formatters: application.formatters, style: styleForCollection)
        case is BookmarkSectionData:
            return BookmarkSectionController(formatters: application.formatters, style: styleForCollection)
        case is MessageSectionData:
            return MessageSectionController(formatters: application.formatters, style: styleForCollection)
        case is TableHeaderData:
            return TableHeaderSectionController(formatters: application.formatters, style: styleForCollection)
        case is TableSectionData:
            return TableSectionController(formatters: application.formatters, style: styleForCollection)
        case is TripStopListItem:
            return TripStopSectionController(formatters: application.formatters, style: styleForCollection)
        default:
            DDLogWarn("You are trying to render \(object), which doesn't have a SectionController mapped to it. Is this a mistake?")
            return LabelSectionController()
        }
    }
}
