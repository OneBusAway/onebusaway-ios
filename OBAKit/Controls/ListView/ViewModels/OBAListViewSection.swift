//
//  OBAListViewSection.swift
//  OBAKit
//
//  Created by Alan Chu on 10/3/20.
//

import UIKit
import OBAKitCore

/// A section view model for `OBAListView`. `OBAListView` uses `OBAListViewSection` to
/// define list sections and to "normalize" item data. It also provides a number of other convenience properties.
///
/// ## Title
/// To add a header to the section, set `title` to non-`nil`. To hide the header, set `title` to nil.
///
/// ## Collapsible sections
/// Set `collapseState` to a non-`nil` value. Note, `OBAListView` will also need to have collapsible
/// section implementation to properly function.
public struct OBAListViewSection: Hashable, Identifiable {
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
    /// - important: OBAListView will override `headerMode` in your custom list configuration, so do not use `headerMode` in your custom configuration.
    public var customListConfiguration: UICollectionLayoutListConfiguration?

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
    }

    subscript(_ itemIndex: Int) -> AnyOBAListViewItem {
        return contents[itemIndex]
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(contents)
    }

    public static func == (lhs: OBAListViewSection, rhs: OBAListViewSection) -> Bool {
        return lhs.title == rhs.title &&
            lhs.contents == rhs.contents
    }
}
