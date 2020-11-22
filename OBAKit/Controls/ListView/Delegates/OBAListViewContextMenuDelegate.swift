//
//  OBAListViewContextMenuDelegate.swift
//  OBAKit
//
//  Created by Alan Chu on 11/1/20.
//

/// To add contextual menus to `OBAListView`, conform to `OBAListViewContextMenuDelegate`.
/// Then, set `OBAListView.contextMenuDelegate`.
public protocol OBAListViewContextMenuDelegate: class {
    /// Provides the configuration for the context menu of the given item.
    /// - parameters:
    ///     - listView: The `OBAListView` that is requesting the context menu.
    ///     - item:     The type-erased `OBAListViewItem` in question. You should always check that item
    ///                 is the type that you want (i.e. `guard let person = item.as(Person.self)`) and
    ///                 gracefully return `nil` if it isn't the expected type.
    /// - returns: The context menu configuration for the given item. If there is no relevant context menu for the item, this will return `nil`.
    func contextMenu(_ listView: OBAListView, for item: AnyOBAListViewItem) -> OBAListViewMenuActions?
}
