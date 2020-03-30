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

    // MARK: - UI

    private lazy var loadMoreLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.textAlignment = .center
        label.font = UIFont.preferredFont(forTextStyle: .body).bold
        label.textColor = ThemeColors.shared.brand
        label.text = OBALoc("stop_controller.load_more_button", value: "Load More", comment: "Load More button")
        return label
    }()

    private lazy var footerLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.textAlignment = .center
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textColor = ThemeColors.shared.secondaryLabel
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let stack = UIStackView.verticalStack(arrangedSubviews: [loadMoreLabel, footerLabel])
        contentView.addSubview(stack)
        stack.pinToSuperview(.layoutMargins)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
