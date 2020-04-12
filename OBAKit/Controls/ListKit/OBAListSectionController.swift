//
//  OBAListSectionController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 3/29/20.
//

import Foundation
import IGListKit
import OBAKitCore

// MARK: - ContextMenuProvider

@available(iOS 13.0, *)
protocol ContextMenuProvider {
    func contextMenuConfiguration(forItemAt indexPath: IndexPath) -> UIContextMenuConfiguration?
}

// MARK: - OBAListSectionControllerInitializer

protocol OBAListSectionControllerInitializer {
    init(formatters: Formatters, style: TableCollectionStyle, hasVisualEffectBackground: Bool)
}

// MARK: - OBAListSectionController

/// An OBAKit-specific subclass of `ListSectionController` meant to be overriden instead of `ListSectionController`.
///
/// Provides easy access to the application-wide `formatters` object, along with the current view controller's table collection style.
class OBAListSectionController<T>: ListSectionController, OBAListSectionControllerInitializer where T: ListDiffable {

    // MARK: - Init

    required init(formatters: Formatters, style: TableCollectionStyle, hasVisualEffectBackground: Bool) {
        self.formatters = formatters
        self.style = style
        self.hasVisualEffectBackground = hasVisualEffectBackground
    }

    // MARK: - Formatters

    let formatters: Formatters

    // MARK: - Style

    let style: TableCollectionStyle

    var isStyleGrouped: Bool { style == .grouped }

    let hasVisualEffectBackground: Bool

    // MARK: - Sizing

    public override func sizeForItem(at index: Int) -> CGSize {
        return CGSize(width: collectionContext!.containerSize.width, height: 40.0)
    }

    // MARK: - Data

    public private(set) var sectionData: T?

    override func didUpdate(to object: Any) {
        guard let object = object as? T else {
            fatalError()
        }

        sectionData = object
    }

    // MARK: - Cells

    /// Dequeues a reusable cell of the specified type.
    ///
    /// This method provides improved ergonomics over `ListSectionController.collectionContext.dequeueReusableCell()`, which it wraps.
    /// - Parameters:
    ///   - type: The cell type to dequeue. Must inherit from `UICollectionViewCell`.
    ///   - index: The row index for which to dequeue a cell.
    /// - Returns: A cell of type `C`, where `C: UICollectionViewCell`.
    func dequeueReusableCell<C>(type: C.Type, at index: Int) -> C where C: UICollectionViewCell {
        guard let cell = collectionContext?.dequeueReusableCell(of: type, for: self, at: index) as? C else {
            fatalError()
        }

        return cell
    }
}
