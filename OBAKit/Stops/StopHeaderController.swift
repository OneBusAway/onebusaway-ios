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
import IGListKit

// MARK: - StopHeaderSection

class StopHeaderSection: NSObject, ListDiffable {
    func diffIdentifier() -> NSObjectProtocol {
        return self
    }

    func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let object = object as? StopHeaderSection else { return false }
        return self == object
    }

    init(stop: Stop, application: Application) {
        self.stop = stop
        self.application = application
    }

    let stop: Stop
    let application: Application
}

// MARK: - StopHeaderSectionController

final class StopHeaderSectionController: OBAListSectionController<StopHeaderSection> {
    override func sizeForItem(at index: Int) -> CGSize {
        // the height of 200 is semi-arbitrary, and was determined by playing around
        // looking for a height that doesn't cause the collection view to be misaligned
        // when it first appears on screen.
        return CGSize(width: collectionContext!.containerSize.width, height: StopHeaderView.headerHeight)
    }

    override func cellForItem(at index: Int) -> UICollectionViewCell {
        let cell = dequeueReusableCell(type: StopHeaderCollectionCell.self, at: index)
        cell.section = sectionData
        return cell
    }
}

// MARK: - StopHeaderCollectionCell

class StopHeaderCollectionCell: SelfSizingCollectionCell {
    let stopHeader = StopHeaderView.autolayoutNew()

    var section: StopHeaderSection? {
        set { stopHeader.section = newValue }
        get { stopHeader.section }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(stopHeader)
        stopHeader.pinToSuperview(.edges)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - StopHeaderView

class StopHeaderView: UIView {
    fileprivate static let headerHeight: CGFloat = 120.0
    private var headerHeight: CGFloat {
        StopHeaderView.headerHeight
    }

    var section: StopHeaderSection? {
        didSet {
            guard let section = section else { return }
            stop = section.stop
        }
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

    private var application: Application {
        section!.application
    }

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

    public var stop: Stop? {
        didSet {
            if stop != oldValue {
                configureView()
            }
        }
    }

    private func configureView() {
        guard let stop = stop else { return }

        let maxWidth = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let size = CGSize(width: maxWidth, height: headerHeight)

        snapshotter = MapSnapshotter(size: size, stopIconFactory: application.stopIconFactory)

        snapshotter?.snapshot(stop: stop, traitCollection: traitCollection) { [weak self] image in
            guard let self = self else { return }
            self.backgroundImageView.image = image
        }

        stopNameLabel.text = stop.name
        stopNumberLabel.text = Formatters.formattedCodeAndDirection(stop: stop)
        routesLabel.text = Formatters.formattedRoutes(stop.routes)

        isAccessibilityElement = true
        accessibilityTraits = [.summaryElement, .header, .staticText]
        accessibilityLabel = stop.name
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
