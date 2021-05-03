//
//  OBAListViewProtocols.swift
//  OBAKit
//
//  Created by Alan Chu on 10/11/20.
//

public protocol OBAListViewDataSource: AnyObject {
    /// Asks the data source for the items to display in the list.
    /// - precondition: The section identifiers must be unique, and the item identifiers in each section
    /// must be unique across all sections.
    ///
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
    /// - returns: The items to display on the list view.
    func items(for listView: OBAListView) -> [OBAListViewSection]

    /// Optional. The view to use as the collection view background when the list is empty.
    /// # Example ViewModel implementation
    /// The following example displays an empty data view using a view model.
    /// ```swift
    /// func emptyData(for listView: OBAListView) -> OBAListView.EmptyData? {
    ///     let viewModel = OBAListView.StandardEmptyDataViewModel(
    ///         title: "No bookmarks",
    ///         body: "Bookmark your frequent trips and stops to quick access them here")
    ///     return .standard(viewModel)
    /// }
    /// ```
    ///
    /// # Example Custom implementation
    /// The following examples display a custom UIView as the empty data. Note that you are responsible for
    /// managing the lifecycle of the view yourself. See `OBAListView.EmptyData` documentation for additional details.
    /// ```swift
    /// lazy var emptyDataView: UIView = CustomEmptyDataView()
    /// func emptyData(for listView: OBAListView) -> OBAListView.EmptyData? {
    ///     return .custom(emptyDataView)
    /// }
    /// ```
    func emptyData(for listView: OBAListView) -> OBAListView.EmptyData?
}

// MARK: - Default implementation

extension OBAListViewDataSource {
    public func emptyData(for listView: OBAListView) -> OBAListView.EmptyData? { return nil }
}
