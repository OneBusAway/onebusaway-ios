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
    var contentConfiguration: OBAContentConfiguration {
        return StopHeaderContentConfiguration(stop: stop, application: application)
    }

    static var customCellType: OBAListViewCell.Type? {
        return StopHeaderCollectionCell.self
    }

    var onSelectAction: OBAListViewAction<StopHeaderItem>?

    var stop: Stop
    var application: Application

    func hash(into hasher: inout Hasher) {
        hasher.combine(stop.id)
    }

    static func == (lhs: StopHeaderItem, rhs: StopHeaderItem) -> Bool {
        return lhs.stop.isEqual(rhs.stop)
    }
}

struct StopHeaderContentConfiguration: OBAContentConfiguration {
    var stop: Stop
    var application: Application
    var formatters: Formatters?
    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return StopHeaderCollectionCell.self
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
    fileprivate static let headerHeight: CGFloat = 120.0
    private var headerHeight: CGFloat {
        StopHeaderView.headerHeight
    }

    private let backgroundImageView: UIImageView = {
        let view = UIImageView.autolayoutNew()
        view.contentMode = .center

        return view
    }()
    private lazy var stopNameLabel = buildLabel(bold: true)
    private lazy var stopNumberLabel = buildLabel()
    private lazy var routesLabel = buildLabel(bold: false, numberOfLines: 0)

    private var snapshotter: MapSnapshotter?

    public override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = ThemeColors.shared.mapSnapshotOverlayColor

        addSubview(backgroundImageView)
        NSLayoutConstraint.activate([
            backgroundImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundImageView.topAnchor.constraint(equalTo: topAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            backgroundImageView.heightAnchor.constraint(equalToConstant: headerHeight)
        ])

        let stack = UIStackView.verticalStack(arrangedSubviews: [stopNameLabel, stopNumberLabel, routesLabel, UIView.autolayoutNew()])
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: readableContentGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: readableContentGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor, constant: ThemeMetrics.padding),
            stack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor)
        ])
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public var config: StopHeaderContentConfiguration? {
        didSet {
            configureView()
        }
    }

    public func configureView() {
        guard let config = config else { return }
        let maxWidth = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let size = CGSize(width: maxWidth, height: headerHeight)

        snapshotter = MapSnapshotter(size: size, stopIconFactory: config.application.stopIconFactory)

        snapshotter?.snapshot(stop: config.stop, traitCollection: traitCollection) { [weak self] image in
            self?.backgroundImageView.image = image
        }

        stopNameLabel.text = config.stop.name
        stopNumberLabel.text = Formatters.formattedCodeAndDirection(stop: config.stop)
        routesLabel.text = Formatters.formattedRoutes(config.stop.routes)

        isAccessibilityElement = true
        accessibilityTraits = [.summaryElement, .header, .staticText]
        accessibilityLabel = config.stop.name
        accessibilityValue = [stopNumberLabel.text, routesLabel.text].compactMap {$0}.joined(separator: " ")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        self.configureView()
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
