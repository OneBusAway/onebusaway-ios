//
//  OBAListViewHeader.swift
//  OBAKit
//
//  Created by Alan Chu on 6/13/21.
//

import UIKit
import OBAKitCore

nonisolated struct OBAListViewHeader: OBAListViewItem {
    let id: String
    let title: String?
    let isCollapsible: Bool

    /// Outline disclosure options configuring chevron style, collapse visibility, and tint.
    var outlineDisclosureOptions: UICellAccessory.OutlineDisclosureOptions {
        UICellAccessory.OutlineDisclosureOptions(
            style: .header,
            isHidden: !isCollapsible,
            reservedLayoutWidth: nil,
            tintColor: ThemeColors.shared.brandTint
        )
    }

    var configuration: OBAListViewItemConfiguration {
        var config = UIListContentConfiguration.header()
        config.text = title
        config.textProperties.font = .preferredFont(forTextStyle: .headline)

        return .list(config, [.outlineDisclosure(displayed: .always, options: outlineDisclosureOptions)])
    }
}
