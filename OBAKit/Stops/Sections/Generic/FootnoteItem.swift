//
//  FootnoteItem.swift
//  OBAKit
//
//  Created by Alan Chu on 7/7/21.
//

import UIKit

struct FootnoteItem: OBAListViewItem {
    var configuration: OBAListViewItemConfiguration {
        var config = UIListContentConfiguration.cell()
        config.textProperties.font = .preferredFont(forTextStyle: .footnote)
        config.textProperties.color = .secondaryLabel
        config.textProperties.alignment = .center
        config.text = self.text

        return .list(config, [])
    }

    var id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}
