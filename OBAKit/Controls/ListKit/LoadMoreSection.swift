//
//  LoadMoreSection.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import IGListKit

final class LoadMoreSectionData: NSObject, ListDiffable {
    func diffIdentifier() -> NSObjectProtocol {
        return self
    }

    func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let object = object as? LoadMoreSectionData else { return false }

        return footerText == object.footerText
    }

    init(footerText: String?, callback: @escaping VoidBlock) {
        self.footerText = footerText
        self.callback = callback
    }

    let footerText: String?
    let callback: VoidBlock
}

final class LoadMoreSectionController: OBAListSectionController<LoadMoreSectionData> {
    override public func cellForItem(at index: Int) -> UICollectionViewCell {
        let cell = dequeueReusableCell(type: LoadMoreCell.self, at: index)
        cell.footerText = sectionData?.footerText

        return cell
    }

    public override func didSelectItem(at index: Int) {
        guard
            let data = sectionData
        else { return }

        data.callback()
    }
}

final class LoadMoreCell: SelfSizingCollectionCell {
    var footerText: String? {
        get { footerLabel.text }
        set { footerLabel.text = newValue }
    }

    private var loadMoreLocalized: String {
        return OBALoc("stop_controller.load_more_button", value: "Load More", comment: "Load More button")
    }

    // MARK: - UI
    private lazy var loadMoreLabel: ProminentButton = {
        let button = ProminentButton(type: .system)
        button.setTitle(loadMoreLocalized, for: .normal)
        button.titleLabel!.font = .preferredFont(forTextStyle: .headline)
        button.titleLabel!.adjustsFontForContentSizeCategory = true
        button.isUserInteractionEnabled = false         // This button is only for visuals.

        return button
    }()

    private lazy var footerLabel: UILabel = {
        let label: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .footnote), textColor: ThemeColors.shared.secondaryLabel)
        label.textAlignment = .center
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let stack = UIStackView.verticalStack(arrangedSubviews: [loadMoreLabel, footerLabel])
        stack.spacing = ThemeMetrics.padding
        stack.alignment = .center
        contentView.addSubview(stack)
        stack.pinToSuperview(.layoutMargins)

        if #available(iOS 13, *) {
            self.largeContentTitle = loadMoreLocalized
            self.showsLargeContentViewer = true
            self.addInteraction(UILargeContentViewerInteraction())
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
