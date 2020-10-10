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

    public var appearance: Appearance = .default
    public var accessoryType: Accessory = .none

    public var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        switch appearance {
        case .default:  return OBAListRowCell<OBAListRowCellDefault>.self
        case .subtitle: return OBAListRowCell<OBAListRowCellSubtitle>.self
        case .value:    return OBAListRowCell<OBAListRowCellValue>.self
        case .header:   return OBAListRowCell<OBAListRowCellHeader>.self
        }
    }
}
