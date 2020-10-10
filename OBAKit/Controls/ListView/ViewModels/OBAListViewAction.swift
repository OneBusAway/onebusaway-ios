//
//  OBAListViewAction.swift
//  OBAKit
//
//  Created by Alan Chu on 10/10/20.
//

import SwipeCellKit

// This needs to be declared by itself. If you declare it under OBAListViewAction,
// it makes it a generic and messes things up.
public enum OBAListViewActionStyle {
    case destructive
    case normal
}

public struct OBAListViewAction<Item: OBAListViewItem> {
    /// The style applied to the action button.
    public var style: OBAListViewActionStyle = .normal

    /// The title of the action button.
    public var title: String? = nil

    /// The image used for the action button.
    public var image: UIImage? = nil

    // MARK: Colors
    /// The text color of the action button.
    public var textColor: UIColor = .white
    
    /// The background color of the action button.
    public var backgroundColor: UIColor = .systemBlue

    // MARK: Behaviors
    /// A Boolean value that determines whether the actions menu is automatically hidden upon selection.
    public var hidesWhenSelected: Bool = false

    public var item: Item? = nil
    public var handler: ((Item) -> Void)? = nil

    public var swipeAction: SwipeAction {
        let style: SwipeActionStyle
        switch self.style {
        case .destructive: style = .destructive
        case .normal: style = .default
        }

        let action = SwipeAction(style: style, title: title) { (action, indexPath) in
            guard let handler = self.handler, let item = self.item else { return }
            handler(item)
        }

        action.image = image
        action.backgroundColor = backgroundColor
        action.hidesWhenSelected = hidesWhenSelected

        return action
    }
}
