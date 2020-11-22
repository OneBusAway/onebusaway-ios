//
//  OBAListViewProtocols.swift
//  OBAKit
//
//  Created by Alan Chu on 10/11/20.
//

public protocol OBAListViewDataSource: class {
    /// The sections you provide must have unique IDs.
    /// # Example implementation
    /// ```swift
    /// func items(for listView: OBAListView) -> [OBAListViewSection] {
    ///     return [
    ///         OBAListViewSection(id: "contacts", title: "Contacts", contents: [
    ///             Person(id: "1", name: "Bob"),
    ///             Person(id: "2", name: "Job"),
    ///             Person(id: "3", name: "Cob")
    ///         ]),
    ///         OBAListViewSection(id: "addresses", title: "Addresses", contents: [
    ///             Address(id: "1", street: "616 Battery St", city: "Seattle"),
    ///             Address(id: "2", intersection: "NE 8th St & Bellevue Way", city: "Bellevue")
    ///         ])
    ///     ]
    /// }
    /// ```
    /// - parameter listView: The list view that is requesting the items.
    func items(for listView: OBAListView) -> [OBAListViewSection]

    /// Optional. The view to use as the collection view background when the list is empty.
    func emptyData(for listView: OBAListView) -> OBAListView.EmptyData?
}

// MARK: - Default implementation

extension OBAListViewDataSource {
    public func emptyData(for listView: OBAListView) -> OBAListView.EmptyData? { return nil }
}
