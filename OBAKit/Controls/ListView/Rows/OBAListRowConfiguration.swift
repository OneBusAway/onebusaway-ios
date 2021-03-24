//
//  OBAListRowConfiguration.swift
//  OBAKit
//
//  Created by Alan Chu on 10/2/20.
//

import OBAKitCore
import UIKit

/// The content configuration view model for `OBAListRowCell`.
///
/// The `appearance` property governs what data may be shown. For example, the `default`
/// appearance will gracefully ignore the `secondaryText` property since it only has one label view.
public struct OBAListRowConfiguration: OBAContentConfiguration, Hashable, Equatable {
    public enum Appearance {
        /// The default look of a list row.
        case `default`

        /// A list row with subtitle text.
        case subtitle

        /// A list row with side-by-side value text.
        case value

        /// A list row with a background to visually separate sections.
        case header
    }

    public enum Accessory {
        case checkmark
        case detailButton
        case disclosureIndicator
        case none
    }

    // Avoids naming conflict with SwiftUI.Text.
    public enum LabelText: Hashable, Equatable {
        case string(String?)
        case attributed(NSAttributedString?)

        public func hash(into hasher: inout Hasher) {
            switch self {
            case .string(let string):
                hasher.combine(string)
            case .attributed(let attributed):
                hasher.combine(attributed)
            }
        }

        public static func == (_ lhs: LabelText, rhs: LabelText) -> Bool {
            switch (lhs, rhs) {
            case (.string(let lhsString), .string(let rhsString)):
                return lhsString == rhsString
            case (.attributed(let lhsAttributed), .attributed(let rhsAttributed)):
                return lhsAttributed == rhsAttributed
            default:
                return false
            }
        }
    }

    public var formatters: Formatters?

    public var image: UIImage?
    public var text: LabelText?
    public var secondaryText: LabelText?

    public var textConfig: OBALabelConfiguration = .init()
    public var secondaryTextConfig: OBALabelConfiguration = .init(textColor: .secondaryLabel)

    public var appearance: Appearance = .default
    public var accessoryType: Accessory = .none

    public var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        switch appearance {
        case .default:  return OBAListRowCell<OBAListRowViewDefault>.self
        case .subtitle: return OBAListRowCell<OBAListRowViewSubtitle>.self
        case .value:    return OBAListRowCell<OBAListRowViewValue>.self
        case .header:   return OBAListRowCell<OBAListRowViewHeader>.self
        }
    }

    public var minimumCellHeight: CGFloat {
        switch appearance {
        case .header:
            return 0
        case .default, .subtitle, .value:
            return 44.0
        }
    }
}

/// A view model defining `UILabel` properties.
/// 
/// Technical Note: This may be expanded in the future, as needed.
public struct OBALabelConfiguration: Hashable, Equatable {
    var textColor: UIColor = .label

    /// The number of lines when the content size is a standard size, aka `UITraitEnvironment.isAccessibility` is `false`.
    var numberOfLines: Int = 0

    /// The number of lines when the content size is an accessibility size, aka `UITraitEnvironment.isAccessibility` is `true`.
    var accessibilityNumberOfLines: Int = 0
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
