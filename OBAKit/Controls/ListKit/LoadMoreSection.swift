//
//  LoadMoreSection.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 4/6/20.
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
        cell.buttonDidTap = { [weak self] in
            self?.sectionData?.callback()
        }

        return cell
    }
}

final class LoadMoreCell: SelfSizingCollectionCell {
    var footerText: String? {
        get { footerLabel.text }
        set { footerLabel.text = newValue }
    }

    var buttonDidTap: VoidBlock?

    // MARK: - UI

    private lazy var loadMoreLabel: ProminentButton = {
        let button = ProminentButton(type: .system)
        button.setTitle(OBALoc("stop_controller.load_more_button", value: "Load More", comment: "Load More button"), for: .normal)
        button.titleLabel!.font = .preferredFont(forTextStyle: .headline)
        button.titleLabel!.adjustsFontForContentSizeCategory = true
        button.addTarget(self, action: #selector(buttonDidTouchUpInsde), for: .touchUpInside)

        if #available(iOS 13, *) {
            button.showsLargeContentViewer = true
            button.addInteraction(UILargeContentViewerInteraction())
        }

        return button
    }()

    private lazy var footerLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = ThemeColors.shared.secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let stack = UIStackView.verticalStack(arrangedSubviews: [loadMoreLabel, footerLabel])
        stack.spacing = ThemeMetrics.padding
        stack.alignment = .center
        contentView.addSubview(stack)
        stack.pinToSuperview(.layoutMargins)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func buttonDidTouchUpInsde(_ sender: Any) {
        self.buttonDidTap?()
    }
}
