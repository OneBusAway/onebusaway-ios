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

        config.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
        config.secondaryTextProperties.color = .tertiaryLabel
        config.secondaryTextProperties.alignment = .center

        config.text = self.text
        config.secondaryText = self.subtitle

        return .list(config, [])
    }

    var id: UUID
    var text: String
    var subtitle: String?

    init(id: UUID = UUID(), text: String, subtitle: String? = nil) {
        self.id = id
        self.text = text
        self.subtitle = subtitle
    }
}
