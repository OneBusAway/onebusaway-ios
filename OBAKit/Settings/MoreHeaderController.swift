//
//  MoreHeaderController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

struct MoreHeaderItem: OBAListViewItem {
    let id: UUID = UUID()

    static var customCellType: OBAListViewCell.Type? {
        return MoreHeaderViewCell.self
    }

    var configuration: OBAListViewItemConfiguration {
        return .custom(MoreHeaderItemContentConfiguration())
    }

    var onSelectAction: OBAListViewAction<MoreHeaderItem>?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MoreHeaderItem, rhs: MoreHeaderItem) -> Bool {
        return lhs.id == rhs.id
    }
}

struct MoreHeaderItemContentConfiguration: OBAContentConfiguration {
    public var formatters: Formatters?
    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return MoreHeaderViewCell.self
    }
}

final class MoreHeaderViewCell: OBAListViewCell {
    let moreHeader = MoreHeaderView.autolayoutNew()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(moreHeader)
        moreHeader.pinToSuperview(.edges)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func apply(_ config: OBAContentConfiguration) {
        // nop.
    }
}

// MARK: - MoreHeaderView
final class MoreHeaderView: UIView {
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
