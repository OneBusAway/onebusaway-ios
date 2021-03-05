//
//  Previewable.swift
//  OBAKit
//
//  Created by Alan Chu on 3/5/21.
//

typealias ControllerPreviewProvider = () -> UIViewController?

/// Implement this protocol on `UIViewController`s that are meant to be viewable as Context Menu previews.
///
/// For more information, read the `ContextMenus.md` tutorial.
protocol Previewable: NSObjectProtocol {
    func enterPreviewMode()
    func exitPreviewMode()
}
