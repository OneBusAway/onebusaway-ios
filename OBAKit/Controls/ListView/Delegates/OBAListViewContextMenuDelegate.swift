//
//  OBAListViewContextMenuDelegate.swift
//  OBAKit
//
//  Created by Alan Chu on 11/1/20.
//

/// To add contextual menus to `OBAListView`, conform to `OBAListViewContextMenuDelegate`.
/// Then, set `OBAListView.contextMenuDelegate`.
public protocol OBAListViewContextMenuDelegate: AnyObject {
    /// Provides the configuration for the context menu of the given item.
    ///
    /// # Example implementation
    /// ```swift
    /// public func contextMenu(_ listView: OBAListView, for item: AnyOBAListViewItem) -> OBAListViewMenuActions? {
    ///     guard let item = item.as(DocumentViewModel.self) else { return nil }
    ///
    ///     // Creates the UIMenu with the applicable menu actions.
    ///     let menu: OBAListViewMenuActions.MenuProvider = { _ -> UIMenu? in
    ///         let children: [UIMenuElement] = [
    ///             UIAction(title: "Save", handler: onSaveAction),
    ///             UIAction(title: "Delete", handler: onDeleteAction)]
    ///
    ///         return UIMenu(title: item.name, children: children)
    ///     }
    ///
    ///     // Creates the view controller to use as the context menu preview (on iOS).
    ///     let previewProvider: OBAListViewMenuActions.PreviewProvider = { () -> UIViewController? in
    ///         return DocumentDetailPreviewViewController(viewModel: item)
    ///     }
    ///
    ///     // The action to perform when the user taps on the context menu preview (on iOS).
    ///     let commitPreviewAction: VoidBlock = {
    ///         self.navigationController?.pushViewController(DocumentDetailViewController(viewModel: item))
    ///     }
    ///
    ///     return OBAListViewMenuActions(
    ///         previewProvider: previewProvider,
    ///         performPreviewAction: commitPreviewAction,
    ///         contextMenuProvider: menu)
    /// }
    /// ```
    /// - parameters:
    ///     - listView: The `OBAListView` that is requesting the context menu.
    ///     - item:     The type-erased `OBAListViewItem` in question. You should always check that item
    ///                 is the type that you want (i.e. `guard let person = item.as(Person.self)`) and
    ///                 gracefully return `nil` if it isn't the expected type.
    /// - returns: The context menu configuration for the given item. If there is no relevant context menu for the item, this will return `nil`.
    func contextMenu(_ listView: OBAListView, for item: AnyOBAListViewItem) -> OBAListViewMenuActions?
}
