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

protocol OBAListViewDelegate: class {
    /// Tells the delegate that the item was selected by the user.
    /// - parameters:
    ///     - listView: The list view where the item was selected.
    ///     - item: The item that was selected.
    func didSelect(_ listView: OBAListView, item: AnyOBAListViewItem)

    /// Tells the delegate that the header for the section was tapped by the user.
    /// - parameters:
    ///     - listView: The list view where the section was tapped.
    ///     - headerView: The header view that was selected. Due to the nature of `OBAListView`'s
    ///         handling of header views, you should update the view directly in this method.
    ///     - section: The section data.
    func didTap(_ listView: OBAListView, headerView: OBAListRowCellHeader, section: OBAListViewSection)

    /// A helper function that handles toggling the collapsed states of sections. This method also updates the provided `headerView`.
    ///
    /// # Default implementation discussion
    /// - If `section.id` exists in `collapsedSection`, then it is removed, the section view model
    ///   is updated, and the model is passed to the header view to update its UI.
    /// - If `section.id` does not exists in `collapsedSection`, then it is added, the section view
    ///   model is updated, and the model is passed to the header view to update its UI.
    ///
    /// # Example usage
    /// Use in `didTap(_ headerView: OBAListRowCellHeader, section: OBAListViewSection)`.
    /// For example:
    /// ```swift
    /// func didTap(_ headerView: OBAListRowCellHeader, section: OBAListViewSection) {
    ///     handleSectionCollapsibleState(didTapHeader: &headerView, forSection: section, collapsedSections: &collapsedSections)
    ///     self.dataSource.apply()
    /// }
    /// ```
    func handleSectionCollapsibleState(
        didTapHeader header: OBAListRowCellHeader,
        forSection section: OBAListViewSection,
        collapsedSections: inout [OBAListViewSection.ID])
}

// MARK: Default implementation
extension OBAListViewDelegate {
    func didTap(_ headerView: OBAListRowCellHeader, section: OBAListViewSection) {
        // nop.
    }

    func handleSectionCollapsibleState(
        didTapHeader header: OBAListRowCellHeader,
        forSection section: OBAListViewSection,
        collapsedSections: inout [OBAListViewSection.ID]) {

        var modifiedSection: OBAListViewSection = section
        if collapsedSections.contains(section.id) {
            modifiedSection.collapseState = .expanded
            collapsedSections.removeAll { $0 == section.id }
        } else {
            modifiedSection.collapseState = .collapsed
            collapsedSections.append(section.id)
        }

        header.section = modifiedSection
    }
}
