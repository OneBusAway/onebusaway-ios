//
//  ListKitExtensions.swift
//  OBANext
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import IGListKit
import OBAKitCore

// swiftlint:disable cyclomatic_complexity

protocol HasTableStyle: NSObjectProtocol {
    var tableStyle: CollectionController.TableCollectionStyle { get }
}

protocol HasVisualEffect: NSObjectProtocol {
    var hasVisualEffectBackground: Bool { get }
}

extension ListAdapterDataSource where Self: AppContext {

    private var styleForCollection: CollectionController.TableCollectionStyle {
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
        return type.init(formatters: application.formatters, style: styleForCollection, hasVisualEffectBackground: isWithinVisualEffectView)
    }

    private func sectionControllerType(for object: Any) -> (ListSectionController & OBAListSectionControllerInitializer).Type {
        switch object {
        case is AgencyAlertsSectionData: return AgencyAlertsSectionController.self
        case is ArrivalDepartureSectionData: return StopArrivalSectionController.self
        case is ServiceAlertsSectionData: return ServiceAlertsSectionController.self
        case is TableHeaderData: return TableHeaderSectionController.self
        case is TableSectionData: return TableSectionController.self
        case is ToggleSectionData: return ToggleSectionController.self
        case is WalkTimeSectionData: return WalkTimeSectionController.self
        default:
            fatalError("You are trying to render \(object), which doesn't have a SectionController mapped to it. This is a mistake!")
        }
    }
}
