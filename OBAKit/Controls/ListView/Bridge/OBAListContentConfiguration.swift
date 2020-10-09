//
//  OBAListContentConfiguration.swift
//  OBAKit
//
//  Created by Alan Chu on 10/2/20.
//

public struct OBAListContentConfiguration: OBAContentConfiguration, Hashable, Equatable {
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

    public var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        switch appearance {
        case .default:  return OBAListViewCell<OBAListRowCellDefault>.self
        case .subtitle: return OBAListViewCell<OBAListRowCellSubtitle>.self
        case .value:    return OBAListViewCell<OBAListRowCellValue>.self
        case .header:   return OBAListViewCell<OBAListRowCellHeader>.self
        }
    }
}
