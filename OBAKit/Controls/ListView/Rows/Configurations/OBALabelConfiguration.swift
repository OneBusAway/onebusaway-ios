//
//  OBALabelConfiguration.swift
//  OBAKit
//
//  Created by Alan Chu on 6/28/21.
//

import Foundation

/// A view model defining `UILabel` properties.
///
/// Technical Note: This may be expanded in the future, as needed.
public struct OBALabelConfiguration: Hashable, Equatable {
    var textColor: UIColor = .label

    /// The number of lines when the content size is a standard size, aka `UITraitEnvironment.isAccessibility` is `false`.
    var numberOfLines: Int = 0

    /// The number of lines when the content size is an accessibility size, aka `UITraitEnvironment.isAccessibility` is `true`.
    var accessibilityNumberOfLines: Int = 0

    func applyToText(_ config: inout UIListContentConfiguration) {
        config.textProperties.color = textColor
        config.textProperties.numberOfLines = numberOfLines
    }

    func applyToSecondaryText(_ config: inout UIListContentConfiguration) {
        config.secondaryTextProperties.color = textColor
        config.secondaryTextProperties.numberOfLines = numberOfLines
    }
}

extension UILabel {
    /// A helper method for configuring a `UILabel` to use `OBALabelConfiguration`.
    func configure(with config: OBALabelConfiguration) {
        self.textColor = config.textColor
        self.numberOfLines = isAccessibility ? config.accessibilityNumberOfLines : config.numberOfLines
    }

    func setText(_ text: OBAListRowConfiguration.LabelText?) {
        if let text = text {
            switch text {
            case .string(let string):
                self.text = string
            case .attributed(let attributed):
                self.attributedText = attributed
            }
        } else {
            self.text = nil // setting text to nil also sets attributed text to nil in UILabel.
        }
    }
}

extension UIListContentConfiguration {
    var labelText: OBAListRowConfiguration.LabelText? {
        get {
            if let text = text {
                return .string(text)
            } else if let attributedText = attributedText {
                return .attributed(attributedText)
            } else {
                return nil
            }
        } set {
            if let labelText = newValue {
                switch labelText {
                case .string(let string): self.text = string
                case .attributed(let text): self.attributedText = text
                }
            } else {
                self.secondaryText = nil
            }
        }
    }

    var secondaryLabelText: OBAListRowConfiguration.LabelText? {
        get {
            if let text = secondaryText {
                return .string(text)
            } else if let attributedText = secondaryAttributedText {
                return .attributed(attributedText)
            } else {
                return nil
            }
        } set {
            if let labelText = newValue {
                switch labelText {
                case .string(let string): self.secondaryText = string
                case .attributed(let text): self.secondaryAttributedText = text
                }
            } else {
                self.secondaryText = nil
            }
        }
    }
}
