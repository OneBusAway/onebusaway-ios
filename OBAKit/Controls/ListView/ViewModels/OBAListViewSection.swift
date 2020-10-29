//
//  OBAListViewSection.swift
//  OBAKit
//
//  Created by Alan Chu on 10/3/20.
//

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

    /// The identifier of this section.
    /// - important: In a given `OBAListView`, this ID must be unique.
    public var id: ID

    /// A localized title that displays in the section header.
    /// If you do not want to display a section header, set this to `nil`.
    public var title: String?

    /// The items in this section.
    public var contents: [AnyOBAListViewItem]

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

    public init<ViewModel: OBAListViewItem>(id: String, title: String? = nil, contents: [ViewModel]) {
        self.id = id
        self.title = title
        self.contents = contents.map { $0.typeErased }
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
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitem: item, count: 1)
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
