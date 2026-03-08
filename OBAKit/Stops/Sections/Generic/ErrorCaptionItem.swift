//
//  ErrorCaptionItem.swift
//  OBAKit
//
//  Created by Alan Chu on 7/12/21.
//

import UIKit
import OBAKitCore

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

    var separatorConfiguration: OBAListRowSeparatorConfiguration { .hidden() }

    var id: UUID
    var text: String

    init(id: UUID = UUID(), error: Error, regionName: String? = nil) {
        self.id = id
        let classified = ErrorClassifier.classify(error, regionName: regionName)
        self.text = classified.localizedDescription
    }

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}
