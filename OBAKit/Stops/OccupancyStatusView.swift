//
//  OccupancyStatusView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/10/21.
//

import UIKit
import OBAKitCore

// swiftlint:disable no_fallthrough_only

/// This view renders the occupancy status of an `ArrivalDeparture` object on a `StopArrivalView`.
///
/// It is displayed as a small badge that shows 1 or more people icons plus a label to denote how full the
/// transit vehicle either is or is likely to be.
class OccupancyStatusView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(outerStack)
        outerStack.pinToSuperview(.edges)

        prepareForReuse()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Data

    private var occupancyStatus: ArrivalDeparture.OccupancyStatus = .unknown
    private var realtimeData = false

    /// Configures the view with the necessary data to populate it.
    /// - Parameters:
    ///   - occupancyStatus: The occupancy status enum value.
    ///   - realtimeData: Whether the occupancy status enum value is real-time or historical.
    func configure(occupancyStatus: ArrivalDeparture.OccupancyStatus, realtimeData: Bool) {
        self.occupancyStatus = occupancyStatus
        self.realtimeData = realtimeData

        guard occupancyStatus != .unknown else {
            isHidden = true
            return
        }

        configureImageViews()
        configureDescriptionLabel()
        tintColor = realtimeData ? .label : .secondaryLabel
    }

    /// Populates the description label with a human readable string describing the occupancy status.
    private func configureDescriptionLabel() {
        var humanReadable: String
        switch occupancyStatus {
        case .empty:
            humanReadable = OBALoc("occupancy_status.empty", value: "Empty", comment: "Vehicle occupancy is zero")
        case .manySeatsAvailable:
            humanReadable = OBALoc("occupancy_status.many_seats_available", value: "Many seats available", comment: "Vehicle occupancy is low")
        case .fewSeatsAvailable:
            humanReadable = OBALoc("occupancy_status.few_seats_available", value: "Few seats available", comment: "Vehicle occupancy is medium")
        case .standingRoomOnly:
            humanReadable = OBALoc("occupancy_status.standing_room_only", value: "Standing room only", comment: "Vehicle occupancy is high")
        case .crushedStandingRoomOnly:
            humanReadable = OBALoc("occupancy_status.crushed_standing_room_only", value: "Crushed standing room only", comment: "Vehicle occupancy is very high")
        case .full:
            humanReadable = OBALoc("occupancy_status.full", value: "Full", comment: "Vehicle occupancy is full")
        case .notAcceptingPassengers:
            humanReadable = OBALoc("occupancy_status.not_accepting_passengers", value: "Not accepting passengers", comment: "Vehicle is not accepting any passengers")
        case .unknown:
            humanReadable = OBALoc("occupancy_status.unknown", value: "Unknown", comment: "Vehicle occupancy status is unknown.")
        }

        if realtimeData {
            descriptionLabel.text = humanReadable
        }
        else {
            let historicalFmt = OBALoc("occupancy_status.historical_fmt", value: "Historical: %@", comment: "A format string that denotes that the associated occupancy status is historical data. e.g. 'Historical: Standing room only'")
            descriptionLabel.text = String(format: historicalFmt, humanReadable)
        }
    }

    /// Populates the passenger image stack or, in the case of a vehicle that is not
    /// accepting passengers, it displays a separate wrapper view that contains a
    /// 'no passengers' badge.
    private func configureImageViews() {
        switch occupancyStatus {
        case .empty: fallthrough
        case .manySeatsAvailable:
            imageStackWrapper.isHidden = false
            outerStack.insertArrangedSubview(imageStackWrapper, at: 0)
            showImageView(at: 0)
        case .fewSeatsAvailable: fallthrough
        case .standingRoomOnly:
            imageStackWrapper.isHidden = false
            outerStack.insertArrangedSubview(imageStackWrapper, at: 0)
            showImageView(at: 0)
            showImageView(at: 1)
        case .crushedStandingRoomOnly: fallthrough
        case .full:
            imageStackWrapper.isHidden = false
            outerStack.insertArrangedSubview(imageStackWrapper, at: 0)
            showImageView(at: 0)
            showImageView(at: 1)
            showImageView(at: 2)
        case .notAcceptingPassengers:
            noPassengersWrapper.isHidden = false
            outerStack.insertArrangedSubview(noPassengersWrapper, at: 0)
        case .unknown:
            break
        }
    }

    /// Prepares the view to be displayed anew. This should be called by parent views' `prepareForReuse` methods.
    func prepareForReuse() {
        for v in personImageViews {
            v.isHidden = true
            imageStackView.removeArrangedSubview(v)
        }

        imageStackWrapper.isHidden = true
        outerStack.removeArrangedSubview(imageStackWrapper)

        noPassengersWrapper.isHidden = true
        outerStack.removeArrangedSubview(noPassengersWrapper)

        descriptionLabel.text = nil

        isHidden = false
    }

    // MARK: - Outer Views

    private lazy var outerStack: UIStackView = {
        let stack = UIStackView.horizontalStack(arrangedSubviews: [imageStackWrapper, descriptionLabel, outerSpacer])
        stack.spacing = ThemeMetrics.padding
        return stack
    }()

    private let outerSpacer: UIView = {
        let v = UIView.autolayoutNew()
        v.setHugging(horizontal: .defaultLow, vertical: .defaultHigh)
        v.setCompressionResistance(horizontal: .defaultLow, vertical: .defaultHigh)

        return v
    }()

    // MARK: - Label

    private lazy var descriptionLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.setHugging(horizontal: .defaultLow, vertical: .defaultLow)
        return label
    }()

    // MARK: - No Passengers Image View

    private lazy var noPassengersImageView: UIImageView = {
        let imageView = buildPersonImageView()
        imageView.image = UIImage(systemName: "person.crop.circle.fill.badge.xmark")
        return imageView
    }()

    private lazy var noPassengersWrapper: UIView = {
        let wrapper = noPassengersImageView.embedInWrapperView()
        wrapper.layer.cornerRadius = 4.0
        wrapper.backgroundColor = .secondarySystemFill
        return wrapper
    }()

    // MARK: - Image Views

    private lazy var imageStackView: UIStackView = {
        let stack = UIStackView.horizontalStack(arrangedSubviews: personImageViews)
        stack.spacing = ThemeMetrics.ultraCompactPadding

        return stack
    }()

    private lazy var imageStackWrapper: UIView = {
        let wrapper = imageStackView.embedInWrapperView()
        wrapper.layer.cornerRadius = 4.0
        wrapper.backgroundColor = .secondarySystemFill
        wrapper.setHugging(horizontal: .defaultHigh, vertical: .defaultHigh)
        return wrapper
    }()

    private lazy var personImageViews = [
        personLeadingImageView,
        personCenterImageView,
        personTrailingImageView,
    ]

    private lazy var personLeadingImageView = buildPersonImageView()
    private lazy var personCenterImageView = buildPersonImageView()
    private lazy var personTrailingImageView = buildPersonImageView()

    private func buildPersonImageView() -> UIImageView {
        let imageView = UIImageView.autolayoutNew()
        imageView.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 20.0)
        ])
        imageView.image = UIImage(systemName: "person.fill")
        imageView.setHugging(horizontal: .required, vertical: .defaultHigh)
        imageView.setCompressionResistance(horizontal: .defaultHigh, vertical: .defaultHigh)
        return imageView
    }

    private func showImageView(at index: Int) {
        let v = personImageViews[index]
        v.isHidden = false
        imageStackView.insertArrangedSubview(v, at: index)
    }
}

#if DEBUG
import SwiftUI

struct OccupancyStatusView_Previews: PreviewProvider {
    private static func buildView(occupancyStatus: ArrivalDeparture.OccupancyStatus, realtimeData: Bool) -> OccupancyStatusView {
        let view = OccupancyStatusView()
        view.configure(occupancyStatus: occupancyStatus, realtimeData: realtimeData)
        return view
    }

    fileprivate static let constrainedFrameStack: UIStackView = {
        let statuses: [ArrivalDeparture.OccupancyStatus] = [
            ArrivalDeparture.OccupancyStatus.unknown,
            ArrivalDeparture.OccupancyStatus.empty,
            ArrivalDeparture.OccupancyStatus.manySeatsAvailable,
            ArrivalDeparture.OccupancyStatus.fewSeatsAvailable,
            ArrivalDeparture.OccupancyStatus.standingRoomOnly,
            ArrivalDeparture.OccupancyStatus.crushedStandingRoomOnly,
            ArrivalDeparture.OccupancyStatus.full,
            ArrivalDeparture.OccupancyStatus.notAcceptingPassengers
        ]

        var views = [UIView]()

        for s in statuses {
            views.append(buildView(occupancyStatus: s, realtimeData: true))
            views.append(buildView(occupancyStatus: s, realtimeData: false))
        }

        let stack = UIStackView.stack(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = 8.0
        return stack
    }()

    static var previews: some View {
        Group {
            UIViewPreview {
                constrainedFrameStack
            }
            .previewLayout(.sizeThatFits)
            .padding()
        }
    }
}

#endif

// swiftlint:enable no_fallthrough_only
