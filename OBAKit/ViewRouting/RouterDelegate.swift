//
//  RouterDelegate.swift
//  OBAKit
//
//  Created by Alan Chu on 3/7/20.
//

import Foundation

/// Provide navigation behavior overrides if necessary.
public protocol ViewRouterDelegate: AnyObject {

    /// Gives an implementing view controller the opportunity to override navigation to a destination controller.
    ///
    /// For instance, you may want to implement this if the current view controller has the ability to better
    /// render the information that will be displayed in the navigation destination.
    func shouldNavigate(to destination: ViewRouter.NavigationDestination) -> Bool
}
