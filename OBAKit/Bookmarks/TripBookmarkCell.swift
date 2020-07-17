//
//  TripBookmarkCell.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import IGListKit
import SwipeCellKit

/// This view displays the information of a `Bookmark`. If the bookmark is a trip, then it will display route,
/// headsign, and predicted arrival/departure times.
///
/// # Trip Layout
/// This view will adapt to accessibility settings.
///
/// ## Standard Content Size
/// ```
/// +----------------------------stackView--------------------------------+
/// |                +-------infoStack-------+  +------minutesStack-----+ |
/// |                | routeHeadsignLabel    |  |   primaryMinutesLabel | |
/// |  pinImageView  |                       |  | secondaryMinutesLabel | |
/// |                | fullExplanationlabel  |  |  tertiaryMinutesLabel | |
/// |                +-----------------------+  +-----------------------+ |
/// +---------------------------------------------------------------------+
/// ```
///
/// ## Accessibility Content Size
/// ```
/// +--------------------------------stackView----------------------------------+
/// | pinImageView                                                              |
/// | +------------------------------infoStack--------------------------------+ |
/// | | routeHeadsignLabel                                                    | |
/// | | accessibilityTimeLabel                                                | |
/// | | accessibilityScheduleDeviationLabel                                   | |
/// | +-----------------------------------------------------------------------+ |
/// | +----------------------------minutesStack-------------------------------+ |
/// | | primaryMinutesLabel    secondaryMinutesLabel     tertiaryMinutesLabel | |
/// | +-----------------------------------------------------------------------+ |
/// +---------------------------------------------------------------------------+
/// ```
///
/// ## Standard → Accessibility:
/// - Display accessibility labels
/// - stackView becomes vertical stack; minutesStack becomes horizontal stack.
final class TripBookmarkTableCell: SwipeCollectionViewCell, SelfSizing, Separated {

    // MARK: - Info Label Stack
    public let routeHeadsignLabel = buildLabel(textStyle: .headline)

    /// Second line in the view; contains the arrival/departure time and status relative to schedule.
    ///
    /// For example, this might contain the text `11:20 AM - arriving on time`.
    private let fullExplanationLabel = buildLabel(textStyle: .body)

    /// Accessibility feature for one-column compact view. For example, `11:20 AM`
    private let accessibilityTimeLabel = buildLabel(textStyle: .subheadline)

    /// Accessibility feature for one-column compact view. For example, `arriving on time`.
    private let accessibilityScheduleDeviationLabel = buildLabel(textStyle: .caption1)

    /// Views to set visible when not in accessibility.
    private var standardInfoStack: [UIView] {
        [fullExplanationLabel]
    }

    /// Views to set visible when user is in accessibility.
    private var accessibilityInfoStack: [UIView] {
        [accessibilityTimeLabel,
         accessibilityScheduleDeviationLabel]
    }

    /// Views containing info elements. To simplify logic, we will include all info views into the stack view.
    private lazy var infoStackView = UIStackView.stack(axis: .vertical, alignment: .leading, arrangedSubviews: [
        routeHeadsignLabel,
        fullExplanationLabel,
        accessibilityTimeLabel,
        accessibilityScheduleDeviationLabel
    ])

    // MARK: - Minutes to Departure Labels
    private lazy var primaryMinutesLabel: DepartureTimeBadge = {
        let label = DepartureTimeBadge.autolayoutNew()
        label.minimumScaleFactor = 3/4
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let secondaryMinutesLabel = TripBookmarkTableCell.buildMinutesLabel
    private let tertiaryMinutesLabel = TripBookmarkTableCell.buildMinutesLabel

    static var buildMinutesLabel: HighlightChangeLabel {
        let label = HighlightChangeLabel.autolayoutNew()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    lazy var minutesStackView = UIStackView(arrangedSubviews: [
        primaryMinutesLabel,
        secondaryMinutesLabel,
        tertiaryMinutesLabel])

    // MARK: - Outer Stack

    lazy var stackView = UIStackView.stack(alignment: .leading, arrangedSubviews: [
        infoStackView,
        minutesStackView
    ])

    // MARK: - UI Builders
    private class func buildLabel(textStyle: UIFont.TextStyle) -> UILabel {
        let label = UILabel.obaLabel(font: .preferredFont(forTextStyle: textStyle))
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setCompressionResistance(horizontal: .required, vertical: .required)
        label.setHugging(horizontal: .defaultLow, vertical: .defaultLow)

        return label
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)

        fixiOS13AutoLayoutBug()

        contentView.backgroundColor = ThemeColors.shared.systemBackground
        contentView.layer.addSublayer(separator)

        contentView.addSubview(stackView)
        stackView.pinToSuperview(.readableContent) { $0.trailing.priority = .required - 1 }

        NSLayoutConstraint.activate([
            primaryMinutesLabel.widthAnchor.constraint(greaterThanOrEqualTo: self.widthAnchor, multiplier: 1/8)
        ])

        isAccessibilityElement = true
        accessibilityTraits = [.button, .updatesFrequently]
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Data

    func configureView(with data: BookmarkArrivalData, formatters: Formatters) {
        routeHeadsignLabel.text = data.bookmark.name

        guard let arrivalDepartures = data.arrivalDepartures else { return }
        if let arrivalDeparture = arrivalDepartures.first {
            fullExplanationLabel.attributedText = formatters.fullAttributedExplanation(from: arrivalDeparture)
            accessibilityTimeLabel.text = formatters.timeFormatter.string(from: arrivalDeparture.arrivalDepartureDate)

            if arrivalDeparture.scheduleStatus == .unknown {
                accessibilityScheduleDeviationLabel.text = Strings.scheduledNotRealTime
            }
            else {
                accessibilityScheduleDeviationLabel.text = formatters.formattedScheduleDeviation(for: arrivalDeparture)
            }

            accessibilityScheduleDeviationLabel.textColor = formatters.colorForScheduleStatus(arrivalDeparture.scheduleStatus)
        }

        // Do accessibility
        standardInfoStack.forEach { $0.isHidden = isAccessibility }
        accessibilityInfoStack.forEach { $0.isHidden = !isAccessibility }

        stackView.axis = isAccessibility ? .vertical : .horizontal
        minutesStackView.axis = isAccessibility ? .horizontal : .vertical

        stackView.spacing = isAccessibility ? ThemeMetrics.accessibilityPadding : ThemeMetrics.compactPadding
        minutesStackView.spacing = isAccessibility ? ThemeMetrics.accessibilityPadding : ThemeMetrics.compactPadding

        minutesStackView.alignment = isAccessibility ? .center : .trailing
        minutesStackView.distribution = isAccessibility ? .fillProportionally : .fill

        // Update data
        func update(view: ArrivalDepartureDrivenUI, withDataAtIndex index: Int) {
            if arrivalDepartures.count > index {
                view.configure(with: arrivalDepartures[index], formatters: formatters)
                view.isHidden = false
            } else {
                view.isHidden = true
            }
        }

        update(view: primaryMinutesLabel, withDataAtIndex: 0)
        update(view: secondaryMinutesLabel, withDataAtIndex: 1)
        update(view: tertiaryMinutesLabel, withDataAtIndex: 2)

        accessibilityLabel = formatters.accessibilityLabel(for: data)
        accessibilityValue = formatters.accessibilityValue(for: data)
    }

    func highlightIfNeeded(newArrivalDepartures: [ArrivalDeparture],
                           basedOn arrivalDepartureTimes: inout ArrivalDepartureTimes) {
        let views: [ArrivalDepartureDrivenUI] = [primaryMinutesLabel, secondaryMinutesLabel, tertiaryMinutesLabel]

        for view in views.enumerated() {
            guard newArrivalDepartures.count > view.offset else { continue }
            let arrDep = newArrivalDepartures[view.offset]
            view.element.highlightIfNeeded(arrivalDeparture: arrDep, basedOn: &arrivalDepartureTimes)
        }
    }

    // MARK: - Separator

    let separator = tableCellSeparatorLayer()

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSeparator()
    }

    // MARK: - UICollectionViewCell Overrides

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        return calculateLayoutAttributesFitting(layoutAttributes)
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        routeHeadsignLabel.text = nil
        fullExplanationLabel.text = nil
        accessibilityTimeLabel.text = nil
        accessibilityScheduleDeviationLabel.text = nil

        primaryMinutesLabel.prepareForReuse()
        secondaryMinutesLabel.text = nil
        tertiaryMinutesLabel.text = nil

        accessibilityLabel = nil
        accessibilityValue = nil
    }

    override var isHighlighted: Bool {
        didSet {
            contentView.backgroundColor = isHighlighted ? ThemeColors.shared.highlightedBackgroundColor : nil
        }
    }
}
