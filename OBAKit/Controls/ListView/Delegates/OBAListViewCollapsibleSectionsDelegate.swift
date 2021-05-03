//
//  OBAListViewCollapsibleSectionsDelegate.swift
//  OBAKit
//
//  Created by Alan Chu on 10/11/20.
//

import UIKit

/// To add collapsible sections to `OBAListView`, conform to `OBAListViewCollapsibleSectionsDelegate`.
/// Then, set `OBAListView.collapsibleSectionsDelegate`.
public protocol OBAListViewCollapsibleSectionsDelegate: AnyObject {
    /// Required. A list of collapsed sections.
    var collapsedSections: Set<OBAListViewSection.ID> { get set }

    /// Optional. Provide taptic feedback when the user collapses a section.
    var selectionFeedbackGenerator: UISelectionFeedbackGenerator? { get }

    /// Optional. Lets OBAListView if you want to exclude sections from being collapsible.
    /// Default implementation returns `true`.
    func canCollapseSection(_ listView: OBAListView, section: OBAListViewSection) -> Bool

    /// Tells the delegate that the header for a section was tapped by the user.
    /// - parameters:
    ///     - listView: The list view where the section was tapped.
    ///     - headerView: The header view that was selected. Due to the nature of `OBAListView`'s
    ///         handling of header views, you should update the view directly in this method.
    ///     - section: The section data.
    func didTap(_ listView: OBAListView, headerView: OBAListRowViewHeader, section: OBAListViewSection)

    /// A helper function that handles toggling the collapsed states of sections. This method also updates the provided `headerView`.
    ///
    /// # Default implementation discussion
    /// - If `section.id` exists in `collapsedSection`, then it is removed, the section view model
    ///   is updated, and the model is passed to the header view to update its UI.
    /// - If `section.id` does not exists in `collapsedSection`, then it is added, the section view
    ///   model is updated, and the model is passed to the header view to update its UI.
    ///
    /// ## Example usage
    /// Use in `didTap(_ headerView: OBAListRowViewHeader, section: OBAListViewSection)`.
    /// For example:
    /// ```swift
    /// func didTap(_ headerView: OBAListRowViewHeader, section: OBAListViewSection) {
    ///     handleSectionCollapsibleState(didTapHeader: &headerView, forSection: section, collapsedSections: &collapsedSections)
    ///     self.dataSource.apply()
    /// }
    /// ```
    /// - parameters:
    ///     - header: The header view that is going to be collapsed/expanded.
    ///     - section: The section view model that was selected
    ///     - collapsedSections: The pointer to the collapsed sections of the current list view.
    func handleSectionCollapsibleState(
        didTapHeader header: OBAListRowViewHeader,
        forSection section: OBAListViewSection,
        collapsedSections: inout Set<OBAListViewSection.ID>)
}

// MARK: Default implementations
extension OBAListViewCollapsibleSectionsDelegate {
    public func canCollapseSection(_ listView: OBAListView, section: OBAListViewSection) -> Bool {
        return true
    }

    public func didTap(_ listView: OBAListView, headerView: OBAListRowViewHeader, section: OBAListViewSection) {
        guard canCollapseSection(listView, section: section) else { return }

        handleSectionCollapsibleState(
            didTapHeader: headerView,
            forSection: section,
            collapsedSections: &collapsedSections)

        // TODO: Animate changes. If we do animate changes right now, the fade animation is really confusing.
        listView.applyData(animated: false)

        selectionFeedbackGenerator?.selectionChanged()
    }

    public func handleSectionCollapsibleState(
        didTapHeader header: OBAListRowViewHeader,
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

        // Update the view with the new state
        header.section = modifiedSection
    }
}
