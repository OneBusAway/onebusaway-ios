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

// swiftlint:disable cyclomatic_complexity

protocol HasTableStyle: NSObjectProtocol {
    var tableStyle: TableCollectionStyle { get }
}

protocol HasVisualEffect: NSObjectProtocol {
    var hasVisualEffectBackground: Bool { get }
}

extension ListAdapterDataSource where Self: AppContext {

    private var styleForCollection: TableCollectionStyle {
        guard let tableStyled = self as? HasTableStyle else {
            return .plain
        }

        return tableStyled.tableStyle
    }

    private var isWithinVisualEffectView: Bool {
        guard let hasEffect = self as? HasVisualEffect else {
            return false
        }

        return hasEffect.hasVisualEffectBackground
    }

    /// Provides a default way to map objects to `ListSectionController` objects.
    ///
    /// Add new section controller types here.
    ///
    /// - Parameter object: An object that will be mapped to a `ListSectionController`
    /// - Returns: The `ListSectionController`
    func defaultSectionController(for object: Any) -> ListSectionController {
        let type = sectionControllerType(for: object)
        return type.init(formatters: application.formatters, style: styleForCollection, hasVisualEffectBackground: true)
    }

    private func sectionControllerType(for object: Any) -> (ListSectionController & OBAListSectionControllerInitializer).Type {
        switch object {
        case is AdjacentTripSection: return AdjacentTripController.self
        case is ArrivalDepartureSectionData: return StopArrivalSectionController.self
        case is BookmarkSectionData: return BookmarkSectionController.self
        case is LoadMoreSectionData: return LoadMoreSectionController.self
        case is MessageSectionData: return MessageSectionController.self
        case is MoreHeaderSection: return MoreHeaderSectionController.self
        case is StopHeaderSection: return StopHeaderSectionController.self
        case is TableHeaderData: return TableHeaderSectionController.self
        case is TableSectionData: return TableSectionController.self
        case is ToggleSectionData: return ToggleSectionController.self
        case is TripStopListItem: return TripStopSectionController.self
        case is WalkTimeSectionData: return WalkTimeSectionController.self
        default:
            fatalError("You are trying to render \(object), which doesn't have a SectionController mapped to it. This is a mistake!")
        }
    }
}
