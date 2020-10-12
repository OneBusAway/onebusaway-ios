//
//  OBAListViewCollapsibleSectionsDelegate.swift
//  OBAKit
//
//  Created by Alan Chu on 10/11/20.
//

/// To add collapsible sections to `OBAListView`, conform to `OBAListViewCollapsibleSectionsDelegate`.
/// Then, set `OBAListView.collapsibleSectionsDelegate`.
protocol OBAListViewCollapsibleSectionsDelegate: class {
    /// Required. A list of collapsed sections.
    var collapsedSections: Set<OBAListViewSection.ID> { get set }

    /// Optional. Provide taptic feedback when the user collapses a section.
    var selectionFeedbackGenerator: UISelectionFeedbackGenerator? { get }

    /// Optional. Default implementation returns `true`.
    func canCollapseSection(_ listView: OBAListView, section: OBAListViewSection) -> Bool

    /// Tells the delegate that the header for a section was tapped by the user.
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
        collapsedSections: inout Set<OBAListViewSection.ID>)
}

// MARK: Default implementations
extension OBAListViewCollapsibleSectionsDelegate {
    func canCollapseSection(_ listView: OBAListView, section: OBAListViewSection) -> Bool {
        return true
    }

    func didTap(_ listView: OBAListView, headerView: OBAListRowCellHeader, section: OBAListViewSection) {
        guard canCollapseSection(listView, section: section) else { return }

        handleSectionCollapsibleState(
            didTapHeader: headerView,
            forSection: section,
            collapsedSections: &collapsedSections)

        // TODO: Animate changes. As it stands, the fade animation is really confusing.
        listView.applyData(animated: false)

        selectionFeedbackGenerator?.selectionChanged()
    }

    func handleSectionCollapsibleState(
        didTapHeader header: OBAListRowCellHeader,
        forSection section: OBAListViewSection,
        collapsedSections: inout Set<OBAListViewSection.ID>) {

        var modifiedSection: OBAListViewSection = section
        if collapsedSections.contains(section.id) {
            modifiedSection.collapseState = .expanded
            collapsedSections.remove(section.id)
        } else {
            modifiedSection.collapseState = .collapsed
            collapsedSections.insert(section.id)
        }

        header.section = modifiedSection
    }
}
