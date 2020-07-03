//
//  TripStopListItem.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/5/19.
//

import UIKit
import IGListKit
import OBAKitCore

fileprivate let tripStopCellMinimumHeight: CGFloat = 48.0

// MARK: - View Model

final class TripStopListItem: NSObject, ListDiffable {

    /// Is this where the vehicle on the trip is currently located?
    let isCurrentVehicleLocation: Bool

    /// Is this the trip stop where the user is intending to go?
    let isUserDestination: Bool

    /// The title of this item. e.g., "15th Ave E & E Galer St"
    let title: String

    /// The `Date` at which the vehicle will arrive/depart this trip stop.
    let date: Date

    /// A formatted representation of `date`
    let formattedDate: String

    /// The route type which will be used to determine the image to display.
    let routeType: Route.RouteType

    /// The `Stop` referred to by this object.
    let stop: Stop

    init(stopTime: TripStopTime, arrivalDeparture: ArrivalDeparture?, formatters: Formatters) {
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
        formattedDate = formatters.timeFormatter.string(from: date)

        routeType = stopTime.stop.prioritizedRouteTypeForDisplay
    }

    // MARK: - ListDiffable

    func diffIdentifier() -> NSObjectProtocol {
        return self
    }

    func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let rhs = object as? TripStopListItem else {
            return false
        }

        return isCurrentVehicleLocation == rhs.isCurrentVehicleLocation &&
            isUserDestination == rhs.isUserDestination &&
            title == rhs.title &&
            date == rhs.date &&
            formattedDate == rhs.formattedDate &&
            routeType == rhs.routeType &&
            stop == rhs.stop
    }
}

// MARK: - Controller

final class TripStopSectionController: OBAListSectionController<TripStopListItem> {
    override func sizeForItem(at index: Int) -> CGSize {
        return CGSize(width: collectionContext!.containerSize.width, height: tripStopCellMinimumHeight)
    }

    override func cellForItem(at index: Int) -> UICollectionViewCell {
        guard let sectionData = sectionData else { fatalError() }

        let cell = dequeueReusableCell(type: TripStopCell.self, at: index)
        cell.titleLabel.text = sectionData.title
        cell.timeLabel.text = sectionData.formattedDate
        cell.tripSegmentView.routeType = sectionData.routeType
        cell.tripSegmentView.setDestinationStatus(user: sectionData.isUserDestination, vehicle: sectionData.isCurrentVehicleLocation)

        return cell
    }

    override func didSelectItem(at index: Int) {
        super.didSelectItem(at: index)

        guard
            let tripStopListItem = sectionData,
            let appContext = viewController as? AppContext
        else { return }

        appContext.application.viewRouter.navigateTo(stop: tripStopListItem.stop, from: appContext)
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
final class TripStopCell: BaseSelfSizingTableCell {
    static let tripSegmentImageWidth: CGFloat = 40.0

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        timeLabel.text = nil
        tripSegmentView.image = nil
        tripSegmentView.adjacentTripOrder = nil
    }

    let titleLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = ThemeColors.shared.label
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    let timeLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = .preferredFont(forTextStyle: .callout)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = ThemeColors.shared.secondaryLabel
        label.numberOfLines = 1
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
            accessoryImageView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            accessoryImageView.widthAnchor.constraint(equalToConstant: 16),
            stackWrapper.trailingAnchor.constraint(equalTo: accessoryImageView.leadingAnchor, constant: -ThemeMetrics.padding)
        ])
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
