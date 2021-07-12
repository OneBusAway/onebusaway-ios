//
//  ErrorCaptionItem.swift
//  OBAKit
//
//  Created by Alan Chu on 7/12/21.
//

import UIKit

struct ErrorCaptionItem: OBAListViewItem {
    var configuration: OBAListViewItemConfiguration {
        var config = UIListContentConfiguration.cell()
        config.textProperties.font = .preferredFont(forTextStyle: .body)
        config.textProperties.color = .label
        config.text = self.text

        config.image = UIImage(systemName: "exclamationmark.triangle.fill")
        config.imageProperties.tintColor = .systemOrange
        config.imageProperties.preferredSymbolConfiguration = .init(textStyle: .headline)

        return .list(config, [])
    }

    var id: UUID
    var text: String

    init(id: UUID = UUID(), error: Error) {
        self.id = id
        self.text = error.localizedDescription
    }
}
