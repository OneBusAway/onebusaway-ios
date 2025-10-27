//
//  OBAListViewHeader.swift
//  OBAKit
//
//  Created by Alan Chu on 6/13/21.
//

import OBAKitCore

struct OBAListViewHeader: OBAListViewItem {
    let id: String
    let title: String?
    let isCollapsible: Bool

    var configuration: OBAListViewItemConfiguration {
        var config = UIListContentConfiguration.header()
        config.text = title
        config.textProperties.font = .preferredFont(forTextStyle: .headline)

        let options = UICellAccessory.OutlineDisclosureOptions(style: .header, isHidden: !isCollapsible, reservedLayoutWidth: nil, tintColor: ThemeColors.shared.brand)
        return .list(config, [.outlineDisclosure(displayed: .always, options: options)])
    }
}
