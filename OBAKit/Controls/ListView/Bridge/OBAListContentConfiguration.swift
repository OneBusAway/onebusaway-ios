//
//  OBAListContentConfiguration.swift
//  OBAKit
//
//  Created by Alan Chu on 10/2/20.
//

import UIKit

public struct OBAListContentConfiguration: Hashable, Equatable {
    public enum Appearance {
        case `default`
        case subtitle
        case value

        case header
    }

    public var image: UIImage? = nil
    public var text: String? = nil
    public var attributedText: NSAttributedString? = nil
    public var secondaryText: String? = nil
    public var secondaryAttributedText: NSAttributedString? = nil

    public var appearance: Appearance = .default

    public var accessoryType: UITableViewCell.AccessoryType = .none

    // MARK: - Bridge
    @available(iOS 14, *)
    public var listContentConfiguration: UIListContentConfiguration {
        var config: UIListContentConfiguration

        switch appearance {
        case .default:   config = .cell()
        case .subtitle:  config = .subtitleCell()
        case .value:     config = .valueCell()
        case .header:    config = .plainHeader()
        }

        config.image = image
        config.text = text
        config.attributedText = attributedText
        config.secondaryText = secondaryText
        config.secondaryAttributedText = secondaryAttributedText

        return config
    }
}
