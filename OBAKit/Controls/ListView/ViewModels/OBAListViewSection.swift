//
//  OBAListViewSection.swift
//  OBAKit
//
//  Created by Alan Chu on 10/3/20.
//

public struct OBAListViewSection: Hashable {
    public enum CollapseState {
        case collapsed
        case expanded
    }

    /// eye deeeee
    public var id: String

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

    public init<ViewModel: OBAListViewItem>(id: String, title: String? = nil, contents: [ViewModel]) {
        self.id = id
        self.title = title
        self.contents = contents.map { AnyOBAListViewItem($0) }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: OBAListViewSection, rhs: OBAListViewSection) -> Bool {
        return lhs.title == rhs.title &&
            lhs.contents == rhs.contents
    }
}
