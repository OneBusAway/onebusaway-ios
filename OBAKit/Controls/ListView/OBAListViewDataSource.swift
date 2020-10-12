//
//  OBAListViewProtocols.swift
//  OBAKit
//
//  Created by Alan Chu on 10/11/20.
//

protocol OBAListViewDataSource: class {
    /// The sections you provide must have unique IDs.
    /// # Example implementation
    /// ```swift
    /// func items(for listView: OBAListView) -> [OBAListViewSection] {
    ///     return [
    ///         OBAListViewSection(id: "contacts", title: "Contacts", contents: [
    ///             Person(name: "Bob"),
    ///             Person(name: "Job"),
    ///             Person(name: "Cob")
    ///         ]),
    ///         OBAListViewSection(id: "addresses", title: "Addresses", contents: [
    ///             Address(street: "616 Battery St", city: "Seattle"),
    ///             Address(street: "NE 8th St & Bellevue Way", city: "Bellevue")
    ///         ])
    ///     ]
    /// }
    /// ```
    /// - parameter listView: The list view that is requesting the items.
    func items(for listView: OBAListView) -> [OBAListViewSection]
}
