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

final class MessageSectionData: ListViewModel, ListDiffable {
    var author: String?
    var date: String?
    var subject: String
    var summary: String?

    /// The maximum number of lines to display for the summary before truncation. Set to `0` for unlimited lines.
    /// - Note: A multiple of this value is used when the user's content size is set to an accessibility size.
    var summaryNumberOfLines: Int = 2

    /// The maximum number of lines to display for the subject before truncation. Set to `0` for unlimited lines.
    /// - Note: A multiple of this value is used when the user's content size is set to an accessibility size.
    var subjectNumberOfLines: Int = 1

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
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let dateLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textColor = ThemeColors.shared.secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let subjectLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let summaryLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.textColor = ThemeColors.shared.secondaryLabel
        label.numberOfLines = 2
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private var topStack: UIStackView!

    // MARK: - Data

    var data: MessageSectionData? {
        didSet {
            configureView()
        }
    }

    // MARK: - UICollectionViewCell

    override func prepareForReuse() {
        super.prepareForReuse()

        authorLabel.text = nil
        dateLabel.text = nil
        subjectLabel.text = nil
        summaryLabel.text = nil

        configureView()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.topStack = UIStackView.horizontalStack(arrangedSubviews: [authorLabel, dateLabel])
        let topWrapper = topStack.embedInWrapperView()

        let outerStack = UIStackView.verticalStack(arrangedSubviews: [topWrapper, subjectLabel, summaryLabel])
        contentView.addSubview(outerStack)

        outerStack.pinToSuperview(.layoutMargins)

        configureView()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        configureView()
    }

    private func configureView() {
        guard let data = data else { return }

        authorLabel.text = data.author
        dateLabel.text = data.date
        subjectLabel.text = data.subject
        summaryLabel.text = data.summary

        topStack.axis = isAccessibility ? .vertical : .horizontal
        authorLabel.numberOfLines = isAccessibility ? 3 : 1

        let subjectNumberOfLines = data.subjectNumberOfLines
        if subjectNumberOfLines > 0 {
            subjectLabel.numberOfLines = isAccessibility ? subjectNumberOfLines * 3 : subjectNumberOfLines
        }
        else {
            subjectLabel.numberOfLines = subjectNumberOfLines
        }

        let summaryNumberOfLines = data.summaryNumberOfLines
        if summaryNumberOfLines > 0 {
            summaryLabel.numberOfLines = isAccessibility ? summaryNumberOfLines * 4 : summaryNumberOfLines
        }
        else {
            summaryLabel.numberOfLines = summaryNumberOfLines
        }

        isAccessibilityElement = true
        accessibilityTraits = data.tapped == nil ? [.staticText] : [.button, .staticText]
        accessibilityLabel = data.subject

        if let date = data.date {
            accessibilityValue = "\(date), \(data.summary ?? "")"
        }
        else {
            accessibilityValue = data.summary
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - MessageSectionController

final class MessageSectionController: OBAListSectionController<MessageSectionData> {
    override public func cellForItem(at index: Int) -> UICollectionViewCell {
        let cell = dequeueReusableCell(type: MessageCell.self, at: index)
        cell.data = sectionData

        return cell
    }

    public override func didSelectItem(at index: Int) {
        guard
            let data = sectionData,
            let tapped = data.tapped
        else { return }

        tapped(data)
    }
}
