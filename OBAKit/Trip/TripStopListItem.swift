//
//  TripStopListItem.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

// MARK: - Temporal State

/// Describes whether a trip stop is in the past, present, or future relative to the vehicle's current position.
enum TripStopTemporalState: Hashable {
    case past
    case current
    case future
}

fileprivate let tripStopCellMinimumHeight: CGFloat = 48.0

struct TripStopListItemRowConfiguration: OBAContentConfiguration {
    var viewModel: TripStopViewModel
    var formatters: Formatters?

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return TripStopCell.self
    }
}

struct TripStopViewModel: OBAListViewItem {
    var id: String { stop.id }

    var configuration: OBAListViewItemConfiguration {
        return .custom(TripStopListItemRowConfiguration(viewModel: self))
    }

    var separatorConfiguration: OBAListRowSeparatorConfiguration {
        return .withInset(leading: TripStopCell.tripSegmentImageWidth + 10.0)
    }

    static var customCellType: OBAListViewCell.Type? {
        return TripStopCell.self
    }

    var onSelectAction: OBAListViewAction<TripStopViewModel>?

    /// Is this where the vehicle on the trip is currently located?
    let isCurrentVehicleLocation: Bool

    /// Is this the trip stop where the user is intending to go?
    let isUserDestination: Bool

    /// Whether this stop is in the past, present, or future relative to the vehicle position.
    let temporalState: TripStopTemporalState

    /// Zero-based index of this stop within the trip.
    let stopIndex: Int

    /// Total number of stops in the trip.
    let totalStops: Int

    /// The title of this item. e.g., "15th Ave E & E Galer St"
    let title: String

    /// The `Date` at which the vehicle will arrive/depart this trip stop.
    let date: Date

    /// The route type which will be used to determine the image to display.
    let routeType: Route.RouteType

    /// The `Stop` referred to by this object.
    let stop: Stop

    let stopTime: TripStopTime

    init(
        stopTime: TripStopTime,
        arrivalDeparture: ArrivalDeparture?,
        stopIndex: Int,
        totalStops: Int,
        closestStopIndex: Int?,
        onSelectAction: OBAListViewAction<TripStopViewModel>?
    ) {
        self.stopTime = stopTime
        self.stopIndex = stopIndex
        self.totalStops = totalStops

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

        if let closestStopIndex = closestStopIndex {
            if stopIndex < closestStopIndex {
                temporalState = .past
            } else if stopIndex == closestStopIndex {
                temporalState = .current
            } else {
                temporalState = .future
            }
        } else {
            temporalState = .future
        }

        title = stopTime.stop.name
        date = stopTime.arrivalDate
        routeType = stopTime.stop.prioritizedRouteTypeForDisplay

        self.onSelectAction = onSelectAction
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isCurrentVehicleLocation)
        hasher.combine(isUserDestination)
        hasher.combine(temporalState)
        hasher.combine(stopIndex)
        hasher.combine(totalStops)
        hasher.combine(title)
        hasher.combine(date)
        hasher.combine(routeType)
    }

    static func == (lhs: TripStopViewModel, rhs: TripStopViewModel) -> Bool {
        return lhs.isCurrentVehicleLocation == rhs.isCurrentVehicleLocation &&
            lhs.isUserDestination == rhs.isUserDestination &&
            lhs.temporalState == rhs.temporalState &&
            lhs.stopIndex == rhs.stopIndex &&
            lhs.totalStops == rhs.totalStops &&
            lhs.title == rhs.title &&
            lhs.date == rhs.date &&
            lhs.routeType == rhs.routeType
    }
}

// MARK: - Cell

/// ## Standard Cell Appearance
/// ```
/// [ |                            ]
/// [ O  15th & Galer     7:25PM   ] <- Title and Time labels appears side-by-side
/// [ |                            ]
/// ```
///
/// ## Accessibility Cell Appearance
/// ```
/// [ |                            ]
/// [ |  15th                      ]
/// [ O  & Galer                   ] <- Title and Time labels appears on top of each other
/// [ |  7:25PM                    ]
/// [ |                            ]
/// ```
final class TripStopCell: OBAListViewCell {
    static let tripSegmentImageWidth: CGFloat = 40.0

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = ThemeColors.shared.label
        timeLabel.text = nil
        timeLabel.textColor = ThemeColors.shared.secondaryLabel
        tripSegmentView.image = nil
        tripSegmentView.adjacentTripOrder = nil
        tripSegmentView.temporalState = .future
        accessibilityLabel = nil
        accessibilityValue = nil
    }

    let titleLabel: UILabel = {
        let label = UILabel.obaLabel(textColor: ThemeColors.shared.label)
        label.numberOfLines = 0
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
            stackWrapper.trailingAnchor.constraint(equalTo: contentView.readableContentGuide.trailingAnchor),
            heightConstraint
        ])

        isAccessibilityElement = true

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.layoutAccessibility()
        }
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
        let viewModel = config.viewModel

        titleLabel.text = viewModel.title
        timeLabel.text = config.formatters?.timeFormatter.string(from: viewModel.date) ?? ""
        tripSegmentView.routeType = viewModel.routeType
        tripSegmentView.temporalState = viewModel.temporalState
        tripSegmentView.setDestinationStatus(user: viewModel.isUserDestination, vehicle: viewModel.isCurrentVehicleLocation)

        applyTemporalStateStyling(viewModel)

        let labels = [viewModel.title, config.formatters?.timeFormatter.string(from: viewModel.date)]
        accessibilityLabel = labels.compactMap { $0 }.joined(separator: "; ")

        var accessibilityValueFlags: [String] = []

        switch viewModel.temporalState {
        case .past:
            accessibilityValueFlags.append(OBALoc("trip_stop.passed_stop.accessibility_label", value: "Passed stop", comment: "Voiceover text explaining that the vehicle has already passed this stop"))
        case .current:
            break
        case .future:
            break
        }

        if viewModel.isUserDestination {
            accessibilityValueFlags.append(OBALoc("trip_stop.user_destination.accessibility_label", value: "Your destination", comment: "Voiceover text explaining that this stop is the user's destination"))
        }

        if viewModel.isCurrentVehicleLocation {
            accessibilityValueFlags.append(OBALoc("trip_stop.vehicle_location.accessibility_label", value: "Vehicle is here", comment: "Voiceover text explaining that the vehicle is currently at this stop"))
        }

        let joined = accessibilityValueFlags.joined(separator: ", ")
        accessibilityValue = joined.isEmpty ? nil : joined
    }

    private func applyTemporalStateStyling(_ viewModel: TripStopViewModel) {
        switch viewModel.temporalState {
        case .past:
            titleLabel.textColor = ThemeColors.shared.secondaryLabel
            timeLabel.textColor = ThemeColors.shared.secondaryLabel

        case .current:
            titleLabel.font = .preferredFont(forTextStyle: .headline)
            titleLabel.textColor = ThemeColors.shared.label
            timeLabel.textColor = ThemeColors.shared.label

        case .future:
            if viewModel.isUserDestination {
                titleLabel.font = .preferredFont(forTextStyle: .headline)
            }
            titleLabel.textColor = ThemeColors.shared.label
            timeLabel.textColor = ThemeColors.shared.secondaryLabel
        }
    }

    private func apply(adjacentTripConfiguration config: AdjacentTripRowConfiguration) {
        let titleFormat: String
        if config.order == .previous {
            titleFormat = OBALoc("trip_details_controller.starts_as_fmt", value: "Starts as %@", comment: "Describes the previous trip of this vehicle. e.g. Starts as 10 - Downtown Seattle")
        } else {
            titleFormat = OBALoc("trip_details_controller.continues_as_fmt", value: "Continues as %@", comment: "Describes the next trip of this vehicle. e.g. Continues as 10 - Downtown Seattle")
        }

        titleLabel.text = String(format: titleFormat, config.routeHeadsign)
        accessibilityLabel = titleLabel.text
        tripSegmentView.adjacentTripOrder = config.order
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutAccessibility()
    }

    func layoutAccessibility() {
        self.textLabelsStack.axis = isAccessibility ? .vertical : .horizontal
        self.textLabelSpacerView.isHidden = isAccessibility
    }
}
