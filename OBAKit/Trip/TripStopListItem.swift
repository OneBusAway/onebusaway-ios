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
    let routeType: RouteType

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

final class TripStopCell: BaseSelfSizingTableCell {

    static let tripSegmentImageWidth: CGFloat = 40.0

    /*
     [ |                             ]
     [ O  15th & Galer 7:25PM      > ]
     [ |                             ]
     */

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        timeLabel.text = nil
        tripSegmentView.image = nil
        tripSegmentView.adjacentTripOrder = nil
    }

    let titleLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.numberOfLines = 0
        label.textColor = ThemeColors.shared.label
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    let timeLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.textColor = ThemeColors.shared.secondaryLabel
        label.numberOfLines = 1
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

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

        let stack = UIStackView.horizontalStack(arrangedSubviews: [tripSegmentView, titleLabel, UIView.autolayoutNew(), timeLabel, accessoryImageView])
        stack.spacing = ThemeMetrics.compactPadding
        let stackWrapper = stack.embedInWrapperView(setConstraints: true)
        contentView.addSubview(stackWrapper)

        let heightConstraint = stackWrapper.heightAnchor.constraint(greaterThanOrEqualToConstant: tripStopCellMinimumHeight)
        heightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            stackWrapper.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackWrapper.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackWrapper.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stackWrapper.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            heightConstraint,
            tripSegmentView.widthAnchor.constraint(equalToConstant: TripStopCell.tripSegmentImageWidth)
        ])
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSeparator(leftSeparatorInset: TripStopCell.tripSegmentImageWidth + 10.0)
    }
}
