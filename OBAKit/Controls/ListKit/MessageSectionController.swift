//
//  MessageSectionController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/28/19.
//

import UIKit
import IGListKit
import SwipeCellKit
import OBAKitCore

// MARK: - MessageSectionData

final public class MessageSectionData: ListViewModel, ListDiffable {
    var author: String?
    var date: String?
    var subject: String
    var summary: String?

    public func diffIdentifier() -> NSObjectProtocol {
        return self
    }

    public func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let rhs = object as? MessageSectionData else {
            return false
        }

        return author == rhs.author && date == rhs.date && subject == rhs.subject && summary == rhs.summary
    }

    public init(author: String?, date: String?, subject: String, summary: String?, tapped: ListRowActionHandler?) {
        self.author = author
        self.date = date
        self.subject = subject
        self.summary = summary

        super.init(tapped: tapped)
    }
}

// MARK: - MessageCell

final class MessageCell: BaseSelfSizingTableCell {

    // MARK: - UI

    private let authorLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        return label
    }()

    private let dateLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textColor = ThemeColors.shared.secondaryLabel
        return label
    }()

    private let subjectLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        return label
    }()

    private let summaryLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.textColor = ThemeColors.shared.secondaryLabel
        label.numberOfLines = 2
        return label
    }()

    // MARK: - Data

    var data: MessageSectionData? {
        didSet {
            guard let data = data else { return }

            authorLabel.text = data.author
            dateLabel.text = data.date
            subjectLabel.text = data.subject
            summaryLabel.text = data.summary
        }
    }

    // MARK: - UICollectionViewCell

    override func prepareForReuse() {
        super.prepareForReuse()

        authorLabel.text = nil
        dateLabel.text = nil
        subjectLabel.text = nil
        summaryLabel.text = nil
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        let topStack = UIStackView.horizontalStack(arrangedSubviews: [authorLabel, dateLabel])
        let topWrapper = topStack.embedInWrapperView()

        let outerStack = UIStackView.verticalStack(arrangedSubviews: [topWrapper, subjectLabel, summaryLabel])
        contentView.addSubview(outerStack)

        outerStack.pinToSuperview(.layoutMargins)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - MessageSectionController

final class MessageSectionController: OBAListSectionController {
    var data: MessageSectionData?

    override public func cellForItem(at index: Int) -> UICollectionViewCell {
        guard let cell = collectionContext?.dequeueReusableCell(of: MessageCell.self, for: self, at: index) as? MessageCell else {
            fatalError()
        }

        cell.data = data

        return cell
    }

    public override func didUpdate(to object: Any) {
        precondition(object is MessageSectionData)
        data = object as? MessageSectionData
    }

    public override func didSelectItem(at index: Int) {
        guard let data = data, let tapped = data.tapped else { return }
        tapped(data)
    }
}
