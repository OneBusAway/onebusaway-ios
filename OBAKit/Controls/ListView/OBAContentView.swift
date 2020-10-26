//
//  OBAContentView.swift
//  OBAKit
//
//  Created by Alan Chu on 10/8/20.
//

import Foundation

/// A view that updates it content based on an `OBAContentConfiguration`.
/// `OBAListView` uses `OBAContentView` to pass cell data to the cell's view.
///
/// This is essentially the same as `UIContentView`. Original documentation:
/// This protocol provides a blueprint for a content view object that renders the
/// content and styling that you define with its configuration. The content view’s
/// configuration encapsulates all of the supported properties and behaviors for
/// content view customization.
public protocol OBAContentView: class {
    /// Applies the new configuration to the view, causing the view to render any updates
    /// to its appearance.
    ///
    /// - parameter config: The configuration to update the view with.
    func apply(_ config: OBAContentConfiguration)
}

/// A view model outlining the properties of an `OBAContentView`.
public protocol OBAContentConfiguration {
    /// Provides the type of the content view cell using this configuration.
    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type { get }
}
