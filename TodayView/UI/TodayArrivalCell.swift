//
//  TodayArrivalCell.swift
//  TodayView
//
//  Created by Aaron Brethorst on 2/12/20.
//

import UIKit
import OBAKitCore

final class TodayArrivalCell: UICollectionViewCell, SelfSizing, Separated {

    // MARK: - Config

    private let kUseDebugColors = false

    // MARK: - UI

    private lazy var outerStack: UIStackView = {
        let stack = UIStackView.horizontalStack(arrangedSubviews: [labelStackWrapper, leadingArrivalWrapper, centerArrivalWrapper, trailingArrivalWrapper])
        stack.spacing = ThemeMetrics.compactPadding
        stack.isUserInteractionEnabled = false

        return stack
    }()

    // MARK: - UI/Labels

    fileprivate lazy var titleLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.backgroundColor = .clear
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .body).bold
        return label
    }()

    fileprivate lazy var subtitleLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.backgroundColor = .clear
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .body)
        return label
    }()

    private lazy var labelStackWrapper: UIView = {
        let stack = UIStackView.verticalStack(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.isUserInteractionEnabled = false
        return stack.embedInWrapperView()
    }()

    // MARK: - UI/ArrivalDeparture Labels

    private lazy var leadingArrival = buildArrivalLabel()
    private lazy var leadingArrivalWrapper = wrapLabel(label: leadingArrival)

    private lazy var centerArrival = buildArrivalLabel()
    private lazy var centerArrivalWrapper = wrapLabel(label: centerArrival)

    private lazy var trailingArrival = buildArrivalLabel()
    private lazy var trailingArrivalWrapper = wrapLabel(label: trailingArrival)

    private func buildArrivalLabel() -> TodayArrivalLabel {
        let label = TodayArrivalLabel.autolayoutNew()
        NSLayoutConstraint.activate([
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: 24.0),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 36.0)
        ])
        return label
    }

    private func wrapLabel(label: TodayArrivalLabel) -> UIView {
        label.setContentHuggingPriority(.required, for: .horizontal)
        let wrapper = label.embedInWrapperView(setConstraints: false)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor)
        ])

        return wrapper
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        contentView.layer.addSublayer(separator)
        contentView.backgroundColor = .clear

        contentView.addSubview(outerStack)
        outerStack.pinToSuperview(.layoutMargins)

        if kUseDebugColors {
            contentView.backgroundColor = .magenta
            titleLabel.backgroundColor = .red
            subtitleLabel.backgroundColor = .green
            leadingArrivalWrapper.backgroundColor = .purple
            centerArrivalWrapper.backgroundColor = .yellow
            trailingArrivalWrapper.backgroundColor = .orange
        }
    }

    func configureArrivalLabel(bookmarkArrivalData: BookmarkArrivalData, index: Int, label: TodayArrivalLabel, formatters: Formatters) {
        let arrivalDepartures = bookmarkArrivalData.arrivalDepartures ?? []
        if arrivalDepartures.count > index {
            let data = arrivalDepartures[index]
            label.setData(arrivalDeparture: data, formatters: formatters)
            label.isHidden = false
        }
        else {
            outerStack.removeArrangedSubview(label)
            label.isHidden = true
        }
    }

    func setData(bookmarkArrivalData: BookmarkArrivalData, formatters: Formatters) {
        titleLabel.text = bookmarkArrivalData.bookmark.name

        if let nextArrivalDeparture = bookmarkArrivalData.arrivalDepartures?.first {
            subtitleLabel.text = formatters.formattedScheduleDeviation(for: nextArrivalDeparture)
        }

        configureArrivalLabel(bookmarkArrivalData: bookmarkArrivalData, index: 0, label: leadingArrival, formatters: formatters)
        configureArrivalLabel(bookmarkArrivalData: bookmarkArrivalData, index: 1, label: centerArrival, formatters: formatters)
        configureArrivalLabel(bookmarkArrivalData: bookmarkArrivalData, index: 2, label: trailingArrival, formatters: formatters)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        subtitleLabel.text = nil
        leadingArrival.prepareForReuse()
        centerArrival.prepareForReuse()
        trailingArrival.prepareForReuse()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            contentView.backgroundColor = isHighlighted ? ThemeColors.shared.highlightedBackgroundColor : nil
        }
    }

    let separator = tableCellSeparatorLayer()

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSeparator()
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        return calculateLayoutAttributesFitting(layoutAttributes)
    }
}
