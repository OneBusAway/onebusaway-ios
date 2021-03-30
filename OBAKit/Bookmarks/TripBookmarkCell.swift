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
final class TripBookmarkTableCell: OBAListViewCell {

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

    // MARK: Should highlight updates on display
    private var primaryLabelHighlightOnDisplay = false
    private var secondaryLabelHighlightOnDisplay = false
    private var tertiaryLabelHighlightOnDisplay = false

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

        contentView.addSubview(stackView)
        stackView.pinToSuperview(.readableContent)

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

    override func apply(_ config: OBAContentConfiguration) {
        guard let config = config as? BookmarkArrivalContentConfiguration else { return }
        routeHeadsignLabel.text = config.viewModel.name

        guard let arrivalDepartures = config.viewModel.arrivalDepartures,
              let formatters = config.formatters else { return }

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
        func update(view: ArrivalDepartureDrivenUI, shouldHighlightOnDisplay: inout Bool, withDataAtIndex index: Int) {
            if arrivalDepartures.count > index {
                view.configure(with: arrivalDepartures[index], formatters: formatters)
                shouldHighlightOnDisplay = config.viewModel.arrivalDeparturesPair[index].shouldHighlightOnDisplay
                view.isHidden = false
            } else {
                view.isHidden = true
            }
        }

        update(view: primaryMinutesLabel, shouldHighlightOnDisplay: &primaryLabelHighlightOnDisplay, withDataAtIndex: 0)
        update(view: secondaryMinutesLabel, shouldHighlightOnDisplay: &secondaryLabelHighlightOnDisplay, withDataAtIndex: 1)
        update(view: tertiaryMinutesLabel, shouldHighlightOnDisplay: &tertiaryLabelHighlightOnDisplay, withDataAtIndex: 2)

        accessibilityLabel = formatters.accessibilityLabel(for: config.viewModel)
        accessibilityValue = formatters.accessibilityValue(for: config.viewModel)
    }

    override func willDisplayCell(in listView: OBAListView) {
        // Highlight arrival departure changes, if needed.
        if primaryLabelHighlightOnDisplay {
            primaryMinutesLabel.highlightBackground()
            primaryLabelHighlightOnDisplay = false
        }

        if secondaryLabelHighlightOnDisplay {
            secondaryMinutesLabel.highlightBackground()
            secondaryLabelHighlightOnDisplay = false
        }

        if tertiaryLabelHighlightOnDisplay {
            tertiaryMinutesLabel.highlightBackground()
            tertiaryLabelHighlightOnDisplay = false
        }
    }

    // MARK: - UICollectionViewCell Overrides

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
