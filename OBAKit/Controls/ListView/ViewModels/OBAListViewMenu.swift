//
//  OBAListViewMenu.swift
//  OBAKit
//
//  Created by Alan Chu on 10/29/20.
//

import OBAKitCore

/// The configuration for adding context menus to `OBAListView` items.
///
/// ## Preview configuration for view controllers
/// - To "peek", use `previewProvider`.
/// - To "pop", use `performPreviewAction`.
///
/// Note that `previewProvider` and `performPreviewAction` is not a replica of Peek and Pop,
/// meaning that it isn't expecting the same view controller to commit when you "Pop", like in 3D Touch.
///
/// For performance, if your preview view controller is the same as your destination view controller, keep an
/// instance of the preview view controller in your parent view controller when `previewProvider` is called.
/// Then, configure `performPreviewAction` to push that preview view controller to the navigation stack.
///
/// `OBAListViewMenuActions` supports the `Previewable` protocol, so it will automatically
/// `enterPreviewMode()` when the user is previewing.
///
/// ## Configuration for menu actions
/// `contextMenuProvider` will provide a list of `suggestedActions` that you may include in your
/// menu, "UIKit collects these actions from responders in the current responder chain. You are not required
/// to include the actions in your menu."
public struct OBAListViewMenuActions {
    public typealias PreviewProvider = () -> UIViewController?
    public typealias MenuProvider = (_ suggestedActions: [UIMenuElement]) -> UIMenu?

    public let previewProvider: PreviewProvider?
    public let performPreviewAction: VoidBlock?
    public let contextMenuProvider: MenuProvider?

    func contextMenuConfiguration(identifier: String?) -> UIContextMenuConfiguration {
        let previewProvider: UIContextMenuContentPreviewProvider = {
            guard let controller = self.previewProvider?() else { return nil }

            if let previewable = controller as? Previewable {
                previewable.enterPreviewMode()
            }

            return controller
        }

        let actionProvider: UIContextMenuActionProvider = { suggestedActions in
            return self.contextMenuProvider?(suggestedActions)
        }

        return UIContextMenuConfiguration(identifier: identifier as NSString?, previewProvider: previewProvider, actionProvider: actionProvider)
    }
}
