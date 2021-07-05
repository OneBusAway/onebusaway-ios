//
//  OBAImageViewConfiguration.swift
//  OBAKit
//
//  Created by Alan Chu on 6/28/21.
//

import OBAKitCore

/// A view model defining `UIListContentConfiguration.ImageProperties` properties.
///
/// Technical Note: This may be expanded in the future, as needed.
public struct OBAImageViewConfiguration: Equatable {
    public var tintColor: UIColor?
    public var maximumSize: CGSize

    // MARK: - Initializers
    init(tintColor: UIColor? = ThemeColors.shared.brand, maximumSize: CGSize = .zero) {
        self.tintColor = tintColor
        self.maximumSize = maximumSize
    }

    static public func tinted(_ color: UIColor) -> Self {
        return self.init(tintColor: color)
    }

    static public func maximumSize(squared: CGFloat) -> Self {
        return self.init(maximumSize: CGSize(width: squared, height: squared))
    }

    // MARK: - Apply
    func apply(to contentConfiguration: inout UIListContentConfiguration) {
        contentConfiguration.imageProperties.tintColor = self.tintColor
        contentConfiguration.imageProperties.maximumSize = self.maximumSize
    }
}
