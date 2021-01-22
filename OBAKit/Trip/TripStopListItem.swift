//
//  TripStopListItem.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import IGListKit
import OBAKitCore

fileprivate let tripStopCellMinimumHeight: CGFloat = 48.0

struct TripStopListItemRowConfiguration: OBAContentConfiguration {
    var viewModel: TripStopViewModel
    var formatters: Formatters?

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return TripStopCell.self
    }
}

struct TripStopViewModel: OBAListViewItem {
    var contentConfiguration: OBAContentConfiguration {
        return TripStopListItemRowConfiguration(viewModel: self)
    }

    static var customCellType: OBAListViewCell.Type? {
        return TripStopCell.self
    }

    var onSelectAction: OBAListViewAction<TripStopViewModel>?

    /// Is this where the vehicle on the trip is currently located?
    let isCurrentVehicleLocation: Bool

    /// Is this the trip stop where the user is intending to go?
    let isUserDestination: Bool

    /// The title of this item. e.g., "15th Ave E & E Galer St"
    let title: String

    /// The `Date` at which the vehicle will arrive/depart this trip stop.
    let date: Date

    /// The route type which will be used to determine the image to display.
    let routeType: Route.RouteType

    /// The `Stop` referred to by this object.
    let stop: Stop

    let stopTime: TripStopTime

    init(stopTime: TripStopTime, arrivalDeparture: ArrivalDeparture?, onSelectAction: OBAListViewAction<TripStopViewModel>?) {
        self.stopTime = stopTime

        stop = stopTime.stop

        if let arrivalDeparture = arrivalDeparture {
            isUserDestination = stopTime.stopID == arrivalDeparture.stopID
        }
        else {
            isUserDestination = false
        }

        if let closestStopID = arrivalDeparture?.tripStatus?.closestStopID {
            isCurrentVehicleLocation = stopTime.stopID == closestStopID
        }
        else {
            isCurrentVehicleLocation = false
        }

        title = stopTime.stop.name
        date = stopTime.arrivalDate
        routeType = stopTime.stop.prioritizedRouteTypeForDisplay

        self.onSelectAction = onSelectAction
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(stop.id)
    }

    static func == (lhs: TripStopViewModel, rhs: TripStopViewModel) -> Bool {
        return lhs.isCurrentVehicleLocation == rhs.isCurrentVehicleLocation &&
            lhs.isUserDestination == rhs.isUserDestination &&
            lhs.title == rhs.title &&
            lhs.date == rhs.date &&
            lhs.routeType == rhs.routeType
    }
}

// MARK: - Cell

/// ## Standard Cell Appearance
/// ```
/// [ |                            ]
/// [ O  15th & Galer     7:25PM > ]
/// [ |                            ]
/// ```
///
/// ## Accessibility Cell Appearance
/// ```
/// [ |                            ]
/// [ |  15th                      ]
/// [ O  & Galer                 > ]
/// [ |  7:25PM                    ]
/// [ |                            ]
/// ```
final class TripStopCell: OBAListViewCell {
    static let tripSegmentImageWidth: CGFloat = 40.0

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        timeLabel.text = nil
        tripSegmentView.image = nil
        tripSegmentView.adjacentTripOrder = nil
    }

    let titleLabel: UILabel = {
        let label = UILabel.obaLabel(textColor: ThemeColors.shared.label)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    let timeLabel: UILabel = {
        let label = UILabel.obaLabel(font: .preferredFont(forTextStyle: .callout),
                                         textColor: ThemeColors.shared.secondaryLabel,
                                         numberOfLines: 1)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    let textLabelSpacerView = UIView.autolayoutNew()
    lazy var textLabelsStack: UIStackView = UIStackView(arrangedSubviews: [titleLabel, textLabelSpacerView, timeLabel])

    let tripSegmentView = TripSegmentView.autolayoutNew()

    private let accessoryImageView: UIView = {
        let imageView = UIImageView.autolayoutNew()
        imageView.contentMode = .scaleAspectFit
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        imageView.image = Icons.from(accessoryType: .disclosureIndicator)
        let wrapper = imageView.embedInWrapperView(setConstraints: false)

        NSLayoutConstraint.activate([
            imageView.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            imageView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: ThemeMetrics.compactPadding),
            imageView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor)
        ])

        return wrapper
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(tripSegmentView)
        NSLayoutConstraint.activate([
            tripSegmentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tripSegmentView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tripSegmentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            tripSegmentView.widthAnchor.constraint(equalToConstant: TripStopCell.tripSegmentImageWidth)
        ])

        let stackWrapper = textLabelsStack.embedInWrapperView(setConstraints: true)
        contentView.addSubview(stackWrapper)

        let heightConstraint = stackWrapper.heightAnchor.constraint(greaterThanOrEqualToConstant: tripStopCellMinimumHeight)
        heightConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stackWrapper.leadingAnchor.constraint(equalTo: tripSegmentView.trailingAnchor, constant: ThemeMetrics.padding),
            stackWrapper.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackWrapper.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            heightConstraint
        ])

        contentView.addSubview(accessoryImageView)
        NSLayoutConstraint.activate([
            accessoryImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            accessoryImageView.trailingAnchor.constraint(equalTo: contentView.readableContentGuide.trailingAnchor),
            accessoryImageView.widthAnchor.constraint(equalToConstant: 16),
            stackWrapper.trailingAnchor.constraint(equalTo: accessoryImageView.leadingAnchor, constant: -ThemeMetrics.padding)
        ])
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Cell configurations
    override func apply(_ config: OBAContentConfiguration) {
        if let tripStopConfig = config as? TripStopListItemRowConfiguration {
            apply(tripStopListItemConfiguration: tripStopConfig)
        } else if let adjacentTripConfig = config as? AdjacentTripRowConfiguration {
            apply(adjacentTripConfiguration: adjacentTripConfig)
        }
    }

    private func apply(tripStopListItemConfiguration config: TripStopListItemRowConfiguration) {
        titleLabel.text = config.viewModel.title
        timeLabel.text = config.formatters?.timeFormatter.string(from: config.viewModel.date) ?? ""
        tripSegmentView.routeType = config.viewModel.routeType
        tripSegmentView.setDestinationStatus(user: config.viewModel.isUserDestination, vehicle: config.viewModel.isCurrentVehicleLocation)
    }

    private func apply(adjacentTripConfiguration config: AdjacentTripRowConfiguration) {
        let titleFormat: String
        if config.order == .previous {
            titleFormat = OBALoc("trip_details_controller.starts_as_fmt", value: "Starts as %@", comment: "Describes the previous trip of this vehicle. e.g. Starts as 10 - Downtown Seattle")
        } else {
            titleFormat = OBALoc("trip_details_controller.continues_as_fmt", value: "Continues as %@", comment: "Describes the next trip of this vehicle. e.g. Continues as 10 - Downtown Seattle")
        }

        titleLabel.text = String(format: titleFormat, config.routeHeadsign)
        tripSegmentView.adjacentTripOrder = config.order
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSeparator(leftSeparatorInset: TripStopCell.tripSegmentImageWidth + 10.0)
        layoutAccessibility()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        layoutAccessibility()
    }

    func layoutAccessibility() {
        self.textLabelsStack.axis = isAccessibility ? .vertical : .horizontal
        self.textLabelSpacerView.isHidden = isAccessibility
    }
}
