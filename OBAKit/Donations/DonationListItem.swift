//
//  DonationListItem.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/30/23.
//

import OBAKitCore
import UIKit

struct DonationListItem: OBAListViewItem {
    var configuration: OBAListViewItemConfiguration {
        return .custom(DonationContentConfiguration(self))
    }

    static var customCellType: OBAListViewCell.Type? {
        return DonationCell.self
    }

    let onSelectAction: OBAListViewAction<DonationListItem>?
    let onLearnMoreAction: OBAListViewAction<DonationListItem>?
    let onCloseAction: OBAListViewAction<DonationListItem>?

    let id: String

    init(onSelectAction: OBAListViewAction<DonationListItem>?, onLearnMoreAction: OBAListViewAction<DonationListItem>?, onCloseAction: OBAListViewAction<DonationListItem>?) {
        self.id = UUID().uuidString
        self.onSelectAction = onSelectAction
        self.onLearnMoreAction = onLearnMoreAction
        self.onCloseAction = onCloseAction
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DonationListItem, rhs: DonationListItem) -> Bool {
        return lhs.id == rhs.id
    }
}

struct DonationContentConfiguration: OBAContentConfiguration {
    var formatters: OBAKitCore.Formatters?

    var viewModel: DonationListItem

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return DonationCell.self
    }

    init(_ viewModel: DonationListItem) {
        self.viewModel = viewModel
    }
}
