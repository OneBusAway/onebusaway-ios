//
//  StopArrivalWalkItem.swift
//  OBAKit
//
//  Created by Alan Chu on 2/24/21.
//

import SwiftUI
import OBAKitCore
import CoreLocation

struct StopArrivalWalkItem: OBAListViewItem {
    var configuration: OBAListViewItemConfiguration {
        return .custom(StopArrivalWalkContentConfiguration(distance: distance, timeToWalk: timeToWalk))
    }

    static var customCellType: OBAListViewCell.Type? {
        return StopArrivalWalkCell.self
    }

    var separatorConfiguration: OBAListRowSeparatorConfiguration {
        return .hidden()
    }

    var onSelectAction: OBAListViewAction<StopArrivalWalkItem>?

    let id: String
    let distance: CLLocationDistance
    let timeToWalk: TimeInterval

    static func == (lhs: StopArrivalWalkItem, rhs: StopArrivalWalkItem) -> Bool {
        return lhs.id == rhs.id &&
            lhs.distance == rhs.distance &&
            lhs.timeToWalk == rhs.timeToWalk
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct StopArrivalWalkContentConfiguration: OBAContentConfiguration {
    var distance: CLLocationDistance
    var timeToWalk: TimeInterval
    var formatters: Formatters?

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return StopArrivalWalkCell.self
    }
}

class StopArrivalWalkCell: OBAListViewCell {

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
        guard let config = config as? StopArrivalWalkContentConfiguration,
              let formatters = config.formatters else { return }

        let banner = WalkTimeBanner(
            content: .walk(distance: config.distance, timeToWalk: config.timeToWalk),
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

    override func prepareForReuse() {
        super.prepareForReuse()
        hostingController?.rootView = WalkTimeBanner(
            content: .walk(distance: 0, timeToWalk: 0),
            formatters: Formatters(locale: .current, calendar: .current, themeColors: ThemeColors.shared)
        )
    }
}
