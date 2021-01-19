//
//  OBAListViewSection.swift
//  OBAKit
//
//  Created by Alan Chu on 10/3/20.
//

import UIKit

/// A section view model for `OBAListView`. `OBAListView` uses `OBAListViewSection` to
/// define list sections and to "normalize" item data. It also provides a number of other convenience properties.
///
/// ## Title
/// To add a header to the section, set `title` to non-`nil`. To hide the header, set `title` to nil.
///
/// ## Collapsible sections
/// Set `collapseState` to a non-`nil` value. Note, `OBAListView` will also need to have collapsible
/// section implementation to properly function.
public struct OBAListViewSection: Hashable {
    public typealias ID = String
    public enum CollapseState {
        case collapsed
        case expanded
    }

    /// A unique section identifier for tracking the section itself.
    public let id: ID

    /// An optional localized title to display on the section header. If this is set to `nil`, then a section
    /// header will not display. Setting this to any non-nil value, including an empty string, will display a
    /// section header.
    public let title: String?

    /// The items of this section. As with `UICollectionViewDiffableDataSource`, the items you
    /// provide must have unique item identifiers.
    public let contents: [AnyOBAListViewItem]

    /// Indicates whether this section should display a section header, which is dependent on the value of `title`.
    public var hasHeader: Bool {
        return title != nil
    }

    /// If `collapseState` is `nil`, this section won't display a collapsible button and won't collapse.
    /// - important: To avoid confusing `UICollectionView` animations, this value is not checked for equality.
    public var collapseState: CollapseState?

    /// Provide an optional custom section layout.
    ///
    /// Instead of creating a custom layout, you may want to consider creating a separate
    /// `UICollectionView` as `OBAListView` is supposed to be a list view, akin to `UITableView`.
    public var customSectionLayout: NSCollectionLayoutSection?

    /// OBAListViewSection is a level-one section on OBAListView.
    /// - parameters:
    ///     - id:       A unique section identifier for tracking the section itself.
    ///     - title:    An optional localized title to display on the section header.
    ///                 If this is set to `nil`, then a section header will not display.
    ///                 Setting this to any non-nil value, including an empty string, will display a section header.
    ///     - contents: The items of this section. As with `UICollectionViewDiffableDataSource`, the items you
    ///                 provide must have unique item identifiers.
    public init<ViewModel: OBAListViewItem>(id: String, title: String? = nil, contents: [ViewModel]) {
        self.id = id
        self.title = title

        // If the contents provided are already type-erased, we don't want to type-erase it again.
        self.contents = contents.map { item in
            if let typeErased = item as? AnyOBAListViewItem {
                return typeErased
            } else {
                return item.typeErased
            }
        }

        #if DEBUG
        // This is helpful to track down where item identifiers are being set.
        // Since this condition is potentially expensive, only run it in DEBUG mode.
        assert(Set(self.contents).count == self.contents.count,
               "The OBAListViewSection contents you provided have one or more of the same item identifier. This will cause a crash with UICollectionView later on!")
        #endif
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: OBAListViewSection, rhs: OBAListViewSection) -> Bool {
        return lhs.title == rhs.title &&
            lhs.contents == rhs.contents
    }

    // MARK: - UICollectionView

    /// The layout defining this section's layout with full width cells.
    var sectionLayout: NSCollectionLayoutSection {
        if let custom = self.customSectionLayout {
            return custom
        }

        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44))
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)

        // Only include supplementary views with headers
        if hasHeader {
            // Section headers
            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(100)
            )
            let sectionHeader = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            sectionHeader.pinToVisibleBounds = true

            if collapseState != nil {
                // Section footers, a thin line is used to animate a fake cell movement
                let footerSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .estimated(2)
                )
                let sectionFooter = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: footerSize,
                    elementKind: UICollectionView.elementKindSectionFooter,
                    alignment: .bottom
                )
                section.boundarySupplementaryItems = [sectionHeader, sectionFooter]
            } else {
                section.boundarySupplementaryItems = [sectionHeader]
            }
        }

        return section
    }
}
