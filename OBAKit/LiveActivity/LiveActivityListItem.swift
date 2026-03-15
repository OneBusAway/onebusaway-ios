//
//  LiveActivityListItem.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import UIKit

/// A simple list row shown in `StopViewController` to start or stop a Live Activity.
struct LiveActivityListItem: OBAListViewItem {

    enum Action {
        case start, stop
    }

    let id: String
    let action: Action
    var onSelectAction: OBAListViewAction<LiveActivityListItem>?

    var configuration: OBAListViewItemConfiguration {
        let title: String
        let image: UIImage?

        switch action {
        case .start:
            title = OBALoc("live_activity.list_item.start", value: "Start Live Activity", comment: "Button to start a Live Activity from the stop page")
            image = UIImage(systemName: "livephoto")
        case .stop:
            title = OBALoc("live_activity.list_item.stop", value: "Stop Live Activity", comment: "Button to stop a Live Activity from the stop page")
            image = UIImage(systemName: "livephoto.slash")
        }

        return .custom(OBAListRowConfiguration(
            image: image,
            text: .string(title),
            secondaryText: nil,
            appearance: .subtitle,
            accessoryType: .none
        ))
    }

    static func == (lhs: LiveActivityListItem, rhs: LiveActivityListItem) -> Bool {
        lhs.id == rhs.id && lhs.action == rhs.action
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(action == .start ? 0 : 1)
    }
}
