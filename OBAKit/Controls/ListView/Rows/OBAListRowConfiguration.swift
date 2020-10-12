//
//  OBAListRowConfiguration.swift
//  OBAKit
//
//  Created by Alan Chu on 10/2/20.
//

public struct OBAListRowConfiguration: OBAContentConfiguration, Hashable, Equatable {
    public enum Appearance {
        case `default`
        case subtitle
        case value

        case header
    }

    public enum Accessory {
        case checkmark
        case detailButton
        case disclosureIndicator
        case none
    }

    public var image: UIImage? = nil
    public var text: String? = nil
    public var secondaryText: String? = nil

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
}

public struct OBALabelConfiguration: Hashable, Equatable {
    var textColor: UIColor = .label

    /// The number of lines when the content size is a standard size, aka `UITraitEnvironment.isAccessibility` is `false`.
    var numberOfLines: Int = 0

    /// The number of lines when the content size is an accessibility size, aka `UITraitEnvironment.isAccessibility` is `true`.
    var accessibilityNumberOfLines: Int = 0
}

extension UILabel {
    func configure(with config: OBALabelConfiguration) {
        self.textColor = config.textColor
        self.numberOfLines = isAccessibility ? config.accessibilityNumberOfLines : config.numberOfLines
    }
}
