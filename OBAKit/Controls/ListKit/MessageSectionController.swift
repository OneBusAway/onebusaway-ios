//
//  MessageSectionController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
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
    var isUnread: Bool

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

        return author == rhs.author && date == rhs.date && subject == rhs.subject && summary == rhs.summary && isUnread == rhs.isUnread
    }

    public init(author: String?, date: String?, subject: String, summary: String?, isUnread: Bool, tapped: ListRowActionHandler?) {
        self.author = author
        self.date = date
        self.subject = subject
        self.summary = summary
        self.isUnread = isUnread

        super.init(tapped: tapped)
    }
}

// MARK: - MessageCell

final class MessageCell: BaseSelfSizingTableCell {

    private let useDebugColors = false

    // MARK: - UI

    private let authorLabel: UILabel = {
        let label = UILabel.obaLabel(font: UIFont.preferredFont(forTextStyle: .subheadline).bold, minimumScaleFactor: 0.9)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }()

    private let dateLabel: UILabel = {
        let label = UILabel.obaLabel(font: .preferredFont(forTextStyle: .footnote), textColor: ThemeColors.shared.secondaryLabel, minimumScaleFactor: 1.0)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let subjectLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .subheadline), minimumScaleFactor: 0.9)
    private let summaryLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .subheadline), textColor: ThemeColors.shared.secondaryLabel, numberOfLines: 2, minimumScaleFactor: 0.9)

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
        self.topStack.spacing = ThemeMetrics.compactPadding
        let topWrapper = topStack.embedInWrapperView()

        let outerStack = UIStackView.verticalStack(arrangedSubviews: [topWrapper, subjectLabel, summaryLabel])
        contentView.addSubview(outerStack)

        outerStack.pinToSuperview(.readableContent) {
            $0.trailing.priority = .required - 1
        }

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
        accessibilityValue = [data.date, data.summary].compactMap {$0}.joined(separator: ", ")

        if useDebugColors {
            authorLabel.backgroundColor = .magenta
            dateLabel.backgroundColor = .purple
            subjectLabel.backgroundColor = .green
            summaryLabel.backgroundColor = .red
            contentView.backgroundColor = .yellow
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
