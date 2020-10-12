//
//  OBAContentView.swift
//  OBAKit
//
//  Created by Alan Chu on 10/8/20.
//

import Foundation

/// The requirements for a content view that you create using a configuration.
/// Akin to `UIContentView`.
///
/// This protocol provides a blueprint for a content view object that renders the
/// content and styling that you define with its configuration. The content view’s
/// configuration encapsulates all of the supported properties and behaviors for
/// content view customization.
public protocol OBAContentView {
    /// Applies the new configuration to the view, causing the view to render any updates
    /// to its appearance.
    ///
    /// - parameter config: The configuration to update the view with.
    func apply(_ config: OBAContentConfiguration)
}

public protocol OBAContentConfiguration {
    /// Provides the type of the content view cell using this configuration.
    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type { get }
}
