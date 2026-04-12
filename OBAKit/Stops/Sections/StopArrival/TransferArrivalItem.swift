//
//  TransferArrivalItem.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import SwiftUI
import OBAKitCore

// MARK: - List Item

struct TransferArrivalItem: OBAListViewItem {
    var configuration: OBAListViewItemConfiguration {
        return .custom(TransferArrivalContentConfiguration(arrivalTime: arrivalTime, routeDisplay: routeDisplay))
    }

    static var customCellType: OBAListViewCell.Type? {
        return TransferArrivalCell.self
    }

    var separatorConfiguration: OBAListRowSeparatorConfiguration {
        return .hidden()
    }

    var onSelectAction: OBAListViewAction<TransferArrivalItem>?

    let id: String
    let arrivalTime: Date
    let routeDisplay: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(arrivalTime)
        hasher.combine(routeDisplay)
    }

    static func == (lhs: TransferArrivalItem, rhs: TransferArrivalItem) -> Bool {
        return lhs.id == rhs.id &&
            lhs.arrivalTime == rhs.arrivalTime &&
            lhs.routeDisplay == rhs.routeDisplay
    }
}

// MARK: - Content Configuration

struct TransferArrivalContentConfiguration: OBAContentConfiguration {
    var arrivalTime: Date
    var routeDisplay: String
    var formatters: Formatters?

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return TransferArrivalCell.self
    }
}

// MARK: - Cell (reuses WalkTimeBanner for identical look)

class TransferArrivalCell: OBAListViewCell {

    private var hostingController: UIHostingController<WalkTimeBanner>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    override func apply(_ config: OBAContentConfiguration) {
        guard let config = config as? TransferArrivalContentConfiguration,
              let formatters = config.formatters else { return }

        let banner = WalkTimeBanner(
            content: .transfer(arrivalTime: config.arrivalTime, routeDisplay: config.routeDisplay),
            formatters: formatters
        )

        if let hc = hostingController {
            hc.rootView = banner
        } else {
            let hc = UIHostingController(rootView: banner)
            hc.view.backgroundColor = .clear
            hc.view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(hc.view)
            NSLayoutConstraint.activate([
                hc.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                hc.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                hc.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hc.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
            ])
            hostingController = hc
        }
    }
}
