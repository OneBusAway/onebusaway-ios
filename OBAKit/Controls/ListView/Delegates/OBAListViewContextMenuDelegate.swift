//
//  OBAListViewContextMenuDelegate.swift
//  OBAKit
//
//  Created by Alan Chu on 11/1/20.
//

/// To add contextual menus to `OBAListView`, conform to `OBAListViewContextMenuDelegate`.
/// Then, set `OBAListView.contextMenuDelegate`.
public protocol OBAListViewContextMenuDelegate: class {
    func contextMenu(_ listView: OBAListView, for item: AnyOBAListViewItem) -> OBAListViewMenuActions?
}
