//
//  MoreHeaderController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/1/19.
//

import UIKit
import OBAKitCore
import IGListKit

// MARK: - MoreHeaderSection

final class MoreHeaderSection: NSObject, ListDiffable {
    func diffIdentifier() -> NSObjectProtocol {
        return self
    }

    func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let object = object as? MoreHeaderSection else { return false }
        return self == object
    }

    init(callback: @escaping VoidBlock) {
        self.callback = callback
    }

    fileprivate let callback: VoidBlock
}

// MARK: MoreHeaderSectionController

final class MoreHeaderSectionController: OBAListSectionController<MoreHeaderSection> {
    override func sizeForItem(at index: Int) -> CGSize {
        // the height of 200 is semi-arbitrary, and was determined by playing around
        // looking for a height that doesn't cause the collection view to be misaligned
        // when it first appears on screen.
        return CGSize(width: collectionContext!.containerSize.width, height: 200)
    }

    override func cellForItem(at index: Int) -> UICollectionViewCell {
        guard let cell = collectionContext?.dequeueReusableCell(of: MoreHeaderCollectionCell.self, for: self, at: index) as? MoreHeaderCollectionCell else {
            fatalError()
        }
        cell.section = sectionData
        return cell
    }
}

// MARK: - MoreHeaderCollectionCell

final class MoreHeaderCollectionCell: SelfSizingCollectionCell {
    let moreHeader = MoreHeaderView.autolayoutNew()

    var section: MoreHeaderSection? {
        set { moreHeader.section = newValue }
        get { moreHeader.section }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(moreHeader)
        moreHeader.pinToSuperview(.edges)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - MoreHeaderView

final class MoreHeaderView: UIView {

    var section: MoreHeaderSection?

    private lazy var stackView = UIStackView.verticalStack(arrangedSubviews: [
        topPaddingView,
        headerImageView,
        interiorPaddingView,
        appNameLabel,
        appVersionLabel,
        copyrightLabel,
        supportUsLabel,
        bottomPaddingView
    ])

    private lazy var topPaddingView: UIView = {
        let view = UIView.autolayoutNew()
        view.heightAnchor.constraint(equalToConstant: ThemeMetrics.controllerMargin).isActive = true
        return view
    }()

    private lazy var headerImageView: UIImageView = {
        let imageView = UIImageView(image: Icons.header)
        imageView.contentMode = .scaleAspectFit
        imageView.heightAnchor.constraint(equalToConstant: 60.0).isActive = true
        return imageView
    }()

    private lazy var interiorPaddingView: UIView = {
        let view = UIView.autolayoutNew()
        view.heightAnchor.constraint(equalToConstant: ThemeMetrics.controllerMargin / 2.0).isActive = true
        return view
    }()

    private lazy var appNameLabel = buildLabel(font: UIFont.preferredFont(forTextStyle: .body).bold)
    private lazy var appVersionLabel = buildLabel()
    private lazy var copyrightLabel = buildLabel()
    private lazy var supportUsLabel = buildLabel()

    private func buildLabel(font: UIFont? = nil) -> UILabel {
        let label = UILabel.autolayoutNew()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = font ?? UIFont.preferredFont(forTextStyle: .footnote)
        label.textColor = ThemeColors.shared.lightText
        return label
    }

    private lazy var bottomPaddingView: UIView = {
        let view = UIView.autolayoutNew()
        view.heightAnchor.constraint(equalToConstant: ThemeMetrics.controllerMargin).isActive = true
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = ThemeColors.shared.brand

        appNameLabel.text = Bundle.main.appName
        appVersionLabel.text = Bundle.main.appVersion
        copyrightLabel.text = Bundle.main.copyright
        supportUsLabel.text = OBALoc("more_header.support_us_label_text", value: "This app is made and supported by volunteers.", comment: "Explanation about how this app is built and maintained by volunteers.")

        addSubview(stackView)
        stackView.pinToSuperview(.layoutMargins)

        let debugTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(enableDebugMode))
        debugTapRecognizer.numberOfTapsRequired = 8
        headerImageView.isUserInteractionEnabled = true
        headerImageView.addGestureRecognizer(debugTapRecognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func enableDebugMode() {
        section?.callback()
    }
}
