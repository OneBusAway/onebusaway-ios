//
//  OBAListViewSection.swift
//  OBAKit
//
//  Created by Alan Chu on 10/3/20.
//

public struct OBAListViewSection: Hashable {
    /// eye deeeee
    public var id: String

    /// A localized title that displays in the section header.
    /// If you do not want to display a section header, set this to `nil`.
    public var title: String?

    /// The items in this section.
    public var contents: [AnyOBAListViewItem]

    /// Inserts the title as the first item for a header view, provided `title != nil`.
    public var listViewItems: [AnyOBAListViewItem] {
        if let title = title {
            var items = self.contents
            items.insert(AnyOBAListViewItem(OBAListViewSectionHeader(title: title)), at: 0)
            return items
        } else {
            return contents
        }
    }

    public var hasHeader: Bool {
        return title != nil
    }

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

struct OBAListViewSectionHeader: OBAListViewItem {
    var title: String

    func listViewConfigurationForThisItem(_ listView: OBAListView) -> OBAListContentConfiguration {
        return .init(text: title)
    }
}
