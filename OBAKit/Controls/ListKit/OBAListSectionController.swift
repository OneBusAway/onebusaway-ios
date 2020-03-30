//
//  OBAListSectionController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 3/29/20.
//

import Foundation
import IGListKit
import OBAKitCore

/// An OBAKit-specific subclass of `ListSectionController` meant to be overriden instead of `ListSectionController`.
///
/// Provides easy access to the application-wide `formatters` object, along with the current view controller's table collection style.
class OBAListSectionController: ListSectionController {

    // MARK: - Init

    init(formatters: Formatters, style: TableCollectionStyle) {
        self.formatters = formatters
        self.style = style
    }

    // MARK: - Formatters

    let formatters: Formatters

    // MARK: - Style

    let style: TableCollectionStyle

    var isStyleGrouped: Bool { style == .grouped }

    // MARK: - Sizing

    public override func sizeForItem(at index: Int) -> CGSize {
        return CGSize(width: collectionContext!.containerSize.width, height: 40.0)
    }
}
