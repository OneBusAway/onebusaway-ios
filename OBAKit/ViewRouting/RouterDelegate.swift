//
//  RouterDelegate.swift
//  OBAKit
//
//  Created by Alan Chu on 3/7/20.
//

import Foundation

/// Provide navigation behavior overrides if necessary.
public protocol ViewRouterDelegate: class {
    func shouldPerformNavigation(to destination: ViewRouter.NavigationDestination) -> Bool
}
