//
//  StopHeaderController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

// MARK: - StopHeaderSection
struct StopHeaderItem: OBAListViewItem {
    var configuration: OBAListViewItemConfiguration {
        return .custom(StopHeaderContentConfiguration(self))
    }

    static var customCellType: OBAListViewCell.Type? {
        return StopHeaderCollectionCell.self
    }

    var onSelectAction: OBAListViewAction<StopHeaderItem>?

    let id: String

    let stop: Stop
    let stopName: String
    let stopNumber: String
    let subtitleText: String

    let stopIconFactory: StopIconFactory

    init(stop: Stop, application: Application) {
        self.id = stop.id
        self.stop = stop
        self.stopName = stop.name
        self.stopNumber = Formatters.formattedCodeAndDirection(stop: stop)

        if let formattedRoutes = Formatters.formattedRoutes(stop.routes), !formattedRoutes.isEmpty {
            self.subtitleText = formattedRoutes
        } else {
            self.subtitleText = Formatters.formattedAgenciesForRoutes(stop.routes)
        }

        self.stopIconFactory = application.stopIconFactory
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(stopName)
        hasher.combine(stopNumber)
        hasher.combine(subtitleText)
    }

    static func == (lhs: StopHeaderItem, rhs: StopHeaderItem) -> Bool {
        return lhs.id == rhs.id &&
            lhs.stopName == rhs.stopName &&
            lhs.stopNumber == rhs.stopNumber &&
            lhs.subtitleText == rhs.subtitleText
    }
}

struct StopHeaderContentConfiguration: OBAContentConfiguration {
    var viewModel: StopHeaderItem
    var formatters: Formatters?

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return StopHeaderCollectionCell.self
    }

    init(_ viewModel: StopHeaderItem) {
        self.viewModel = viewModel
    }
}

// MARK: - StopHeaderCollectionCell

class StopHeaderCollectionCell: OBAListViewCell {
    let stopHeader = StopHeaderView.autolayoutNew()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(stopHeader)
        stopHeader.pinToSuperview(.edges)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func apply(_ config: OBAContentConfiguration) {
        guard let config = config as? StopHeaderContentConfiguration else { return }
        stopHeader.config = config
    }
}

// MARK: - StopHeaderView

class StopHeaderView: UIView {
    fileprivate static let minimumHeight: CGFloat = 128.0
    // ↓ Arbitrary height, seems to work OK for most text sizes, too large and the map snapshot will take too long to render.
    fileprivate static let maximumHeight: CGFloat = 360.0

    private let backgroundImageView: UIImageView = {
        let view = UIImageView.autolayoutNew()
        view.contentMode = .center

        return view
    }()
    private lazy var stopNameLabel = buildLabel(bold: true)
    private lazy var stopNumberLabel = buildLabel()
    private lazy var routesLabel = buildLabel(bold: false, numberOfLines: 0)
    private var stackPaddingBottomHeight: NSLayoutConstraint!

    private var isHidingRoutesLabel: Bool = false
    private lazy var toggleRouteDetailsGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(toggleRouteDetails))

    private var snapshotter: MapSnapshotter?

    public override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = ThemeColors.shared.mapSnapshotOverlayColor

        // To avoid broken constraints, the backgroundImageView "floats" rather than being constrained on its sides.
        addSubview(backgroundImageView)
        NSLayoutConstraint.activate([
            backgroundImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            backgroundImageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        let stackPaddingBottom = UIView.autolayoutNew()
        self.stackPaddingBottomHeight = stackPaddingBottom.heightAnchor.constraint(equalToConstant: 0)
        self.stackPaddingBottomHeight.priority = .defaultLow

        NSLayoutConstraint.activate([self.stackPaddingBottomHeight])

        let stack = UIStackView.verticalStack(arrangedSubviews: [stopNameLabel, stopNumberLabel, routesLabel, stackPaddingBottom])
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: readableContentGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: readableContentGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor, constant: ThemeMetrics.padding),
            stack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor, constant: -ThemeMetrics.padding),
            stack.heightAnchor.constraint(greaterThanOrEqualToConstant: StopHeaderView.minimumHeight),
            stack.heightAnchor.constraint(lessThanOrEqualToConstant: StopHeaderView.maximumHeight)
        ])

        addGestureRecognizer(toggleRouteDetailsGestureRecognizer)

        let sizeTraits: [UITrait] = [UITraitVerticalSizeClass.self, UITraitHorizontalSizeClass.self]
        registerForTraitChanges(sizeTraits) { (self: Self, _) in
            self.configureView()
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public var config: StopHeaderContentConfiguration? {
        didSet {
            configureView()
        }
    }

    public func configureView() {
        guard let config = config else { return }

        let width = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let size = CGSize(width: width, height: StopHeaderView.maximumHeight)

        snapshotter = MapSnapshotter(size: size, stopIconFactory: config.viewModel.stopIconFactory)

        snapshotter?.snapshot(stop: config.viewModel.stop, traitCollection: traitCollection) { [weak self] image in
            self?.backgroundImageView.image = image
        }

        stopNameLabel.text = config.viewModel.stopName
        stopNumberLabel.text = config.viewModel.stopNumber
        routesLabel.text = config.viewModel.subtitleText

        isAccessibilityElement = true
        accessibilityTraits = [.summaryElement, .header, .staticText]
        accessibilityLabel = config.viewModel.stopName
        accessibilityValue = [stopNumberLabel.text, routesLabel.text].compactMap {$0}.joined(separator: " ")
    }

    override func layoutSubviews() {
        // Adjust the bottom padding view dynamically (i.e. when font size changed).
        super.layoutSubviews()

        let stopNameLabelSize = stopNameLabel.systemLayoutSizeFitting(UIView.layoutFittingExpandedSize)
        let stopNumberLabelSize = stopNumberLabel.systemLayoutSizeFitting(UIView.layoutFittingExpandedSize)
        let routesLabelSize = routesLabel.systemLayoutSizeFitting(UIView.layoutFittingExpandedSize)
        let sumOfHeights = stopNameLabelSize.height + stopNumberLabelSize.height + routesLabelSize.height

        let suggestedHeight: CGFloat
        if sumOfHeights < StopHeaderView.minimumHeight {
            suggestedHeight = StopHeaderView.minimumHeight - sumOfHeights
        } else {
            suggestedHeight = 0
        }

        self.stackPaddingBottomHeight.constant = suggestedHeight
    }

    @objc private func toggleRouteDetails(_ sender: UITapGestureRecognizer) {
        isHidingRoutesLabel.toggle()
        routesLabel.alpha = isHidingRoutesLabel ? 1.0 : 0.0
    }

    private func buildLabel(bold: Bool = false, numberOfLines: Int = 1) -> UILabel {
        let label = UILabel.autolayoutNew()
        label.textColor = .white
        label.shadowColor = .black
        label.numberOfLines = numberOfLines
        label.shadowOffset = CGSize(width: 0, height: 1)
        label.font = UIFont.preferredFont(forTextStyle: (bold ? .headline : .body))
        label.adjustsFontForContentSizeCategory = false
        return label
    }
}
