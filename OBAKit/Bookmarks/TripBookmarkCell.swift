//
//  TripBookmarkCell.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 2/15/20.
//

import UIKit
import OBAKitCore
import IGListKit
import SwipeCellKit

final class TripBookmarkTableCell: SwipeCollectionViewCell, SelfSizing, Separated {

    // MARK: - Info Label Stack

    public let routeHeadsignLabel: UILabel = {
        let label = buildLabel()
        label.numberOfLines = 0
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }()

    private lazy var favoriteImageView: UIImageView = {
        let imageView = UIImageView.autolayoutNew()
        imageView.image = Icons.star
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = ThemeColors.shared.label
        imageView.setContentHuggingPriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            imageView.heightAnchor.constraint(equalToConstant: 16.0),
            imageView.widthAnchor.constraint(equalToConstant: 16.0)
        ])

        return imageView
    }()

    private lazy var routeHeadsignStack: UIStackView = {
        let stack = UIStackView.horizontalStack(arrangedSubviews: [favoriteImageView, routeHeadsignLabel])
        return stack
    }()

    private lazy var routeHeadsignWrapper = routeHeadsignStack.embedInWrapperView()

    /// Second line in the view; contains the arrival/departure time and status relative to schedule.
    ///
    /// For example, this might contain the text `11:20 AM - arriving on time`.
    let timeExplanationLabel = buildLabel()

    lazy var labelStack = UIStackView.verticalStack(arrangedSubviews: [routeHeadsignWrapper, timeExplanationLabel, UIView.autolayoutNew()])

    // MARK: - Minutes to Departure Labels

    /// Appears on the trailing side of the view; contains the number of minutes until arrival/departure.
    ///
    /// For example, this might contain the text `10m`.
    let topMinutesLabel = HighlightChangeLabel.autolayoutNew()

    private lazy var topMinutesWrapper = buildMinutesLabelWrapper(label: topMinutesLabel)

    let centerMinutesLabel = HighlightChangeLabel.autolayoutNew()

    private lazy var centerMinutesWrapper = buildMinutesLabelWrapper(label: centerMinutesLabel)

    let bottomMinutesLabel = HighlightChangeLabel.autolayoutNew()

    private lazy var bottomMinutesWrapper = buildMinutesLabelWrapper(label: bottomMinutesLabel)

    private lazy var minutesStack = UIStackView.verticalStack(arrangedSubviews: [topMinutesWrapper, centerMinutesWrapper, bottomMinutesWrapper])

    private lazy var minutesWrappers: UIView = {
        let wrapper = minutesStack.embedInWrapperView(setConstraints: false)
        NSLayoutConstraint.activate([
            minutesStack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            minutesStack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            minutesStack.topAnchor.constraint(equalTo: wrapper.topAnchor),
            minutesStack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])

        return wrapper
    }()

    // MARK: - Outer Stack

    lazy var outerStack = UIStackView.horizontalStack(arrangedSubviews: [labelStack, minutesWrappers])

    // MARK: - UI Builders

    private class func buildLabel() -> UILabel {
        let label = UILabel.autolayoutNew()
        label.setCompressionResistance(horizontal: .required, vertical: .required)
        label.setHugging(horizontal: .defaultLow, vertical: .defaultLow)
        return label
    }

    private func buildMinutesLabelWrapper(label: UILabel) -> UIView {
        let wrapper = label.embedInWrapperView()
        wrapper.setCompressionResistance(horizontal: .required, vertical: .required)
        return wrapper
    }

    // MARK: - Data

    public func set(data: BookmarkArrivalData, formatters: Formatters) {
        self.formatters = formatters
        self.data = data
    }

    var data: BookmarkArrivalData? {
        didSet {
            guard let data = data else { return }

            let isFavorite = data.bookmark.isFavorite
            let isFavoriteViewInstalled = routeHeadsignStack.arrangedSubviews.contains(favoriteImageView)

            switch (isFavorite, isFavoriteViewInstalled) {
            case (true, false):
                routeHeadsignStack.insertArrangedSubview(favoriteImageView, at: 0)
                favoriteImageView.isHidden = false
            case (false, true):
                routeHeadsignStack.removeArrangedSubview(favoriteImageView)
                favoriteImageView.isHidden = true
            default: break // true/true and false/false are both nops.
            }

            routeHeadsignLabel.text = data.bookmark.name
            arrivalDepartures = data.arrivalDepartures
        }
    }

    /// Set this to display up to three `ArrivalDeparture`s in this view.
    private var arrivalDepartures: [ArrivalDeparture]? {
        didSet {
            guard let arrivalDepartures = arrivalDepartures else { return }

            if let first = arrivalDepartures.first {
                timeExplanationLabel.attributedText = formatters.fullAttributedExplanation(from: first)
            }

            let updateLabelWithDeparture = { (label: UILabel, wrapper: UIView, index: Int) in
                if arrivalDepartures.count > index {
                    let dep = arrivalDepartures[index]
                    label.text = self.formatters.shortFormattedTime(until: dep)
                    label.textColor = self.formatters.colorForScheduleStatus(dep.scheduleStatus)
                    self.minutesStack.insertArrangedSubview(wrapper, at: index)
                }
                else {
                    wrapper.removeFromSuperview()
                    label.text = nil
                }
            }

            updateLabelWithDeparture(topMinutesLabel, topMinutesWrapper, 0)
            updateLabelWithDeparture(centerMinutesLabel, centerMinutesWrapper, 1)
            updateLabelWithDeparture(bottomMinutesLabel, bottomMinutesWrapper, 2)
        }
    }

    private var formatters: Formatters!

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)

        fixiOS13AutoLayoutBug()

        contentView.backgroundColor = ThemeColors.shared.systemBackground
        contentView.layer.addSublayer(separator)

        contentView.addSubview(outerStack)
        outerStack.pinToSuperview(.layoutMargins)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        timeExplanationLabel.text = nil
        topMinutesLabel.text = ""
        centerMinutesLabel.text = ""
        bottomMinutesLabel.text = ""
    }

    override var isHighlighted: Bool {
        didSet {
            contentView.backgroundColor = isHighlighted ? ThemeColors.shared.highlightedBackgroundColor : nil
        }
    }
}
