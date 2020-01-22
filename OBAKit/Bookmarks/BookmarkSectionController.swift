//
//  BookmarkSectionController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/12/20.
//

import UIKit
import IGListKit
import OBAKitCore
import SwipeCellKit

enum BookmarkSectionState: String, Codable {
    case open, closed

    func toggledValue() -> BookmarkSectionState {
        return self == .open ? .closed : .open
    }
}

typealias BookmarkListCallback = (Bookmark) -> Void
typealias BookmarkSectionToggled = (BookmarkSectionData, BookmarkSectionState) -> Void

/// A view model used with `IGListKit` to display `Bookmark` data in the `BookmarksViewController`.
class BookmarkArrivalData: NSObject, ListDiffable {
    public let bookmark: Bookmark
    public let arrivalDepartures: [ArrivalDeparture]?
    let selected: BookmarkListCallback
    let deleted: BookmarkListCallback
    let edited: BookmarkListCallback

    public init(bookmark: Bookmark, arrivalDepartures: [ArrivalDeparture]?, selected: @escaping BookmarkListCallback, deleted: @escaping BookmarkListCallback, edited: @escaping BookmarkListCallback) {
        self.bookmark = bookmark
        self.arrivalDepartures = arrivalDepartures
        self.selected = selected
        self.deleted = deleted
        self.edited = edited
    }

    public func diffIdentifier() -> NSObjectProtocol {
        bookmark.id as NSObjectProtocol
    }

    public func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let object = object as? BookmarkArrivalData else {
            return false
        }

        return bookmark == object.bookmark && arrivalDepartures == object.arrivalDepartures
    }

    override var debugDescription: String {
        var descriptionBuilder = DebugDescriptionBuilder(baseDescription: super.debugDescription)
        descriptionBuilder.add(key: "bookmark", value: bookmark)
        descriptionBuilder.add(key: "arrivalDepartures", value: arrivalDepartures)
        return descriptionBuilder.description
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(bookmark)
        hasher.combine(arrivalDepartures)
        return hasher.finalize()
    }
}

/// A view model for displaying a `BookmarkGroup` and its `Bookmark`s in the `BookmarksViewController`.
class BookmarkSectionData: NSObject, ListDiffable {
    public let group: BookmarkGroup?
    public let title: String?
    public let bookmarks: [BookmarkArrivalData]

    public var state: BookmarkSectionState = .closed

    let toggled: BookmarkSectionToggled

    /// Creates a new `BookmarkSectionData` object.
    /// - Parameter group: The `BookmarkGroup` that will populate this data object.
    /// - Parameter title: The title of the section that will be displayed in the UI on a section header.
    /// - Parameter bookmarkArrivalData: The `BookmarkArrivalData` objects that belong to `group`.
    /// - Parameter toggled: A closure invoked when the user toggles the section open or closed.
    public init(group: BookmarkGroup?, title: String?, bookmarkArrivalData: [BookmarkArrivalData], toggled: @escaping BookmarkSectionToggled) {
        self.group = group
        self.title = title
        self.bookmarks = bookmarkArrivalData
        self.toggled = toggled
    }

    public func diffIdentifier() -> NSObjectProtocol {
        if let group = group {
            return group.id as NSObjectProtocol
        }
        else {
            return self as NSObjectProtocol
        }
    }

    public func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let groupData = object as? BookmarkSectionData else {
            return false
        }

        return group == groupData.group && title == groupData.title && bookmarks == groupData.bookmarks && state == groupData.state
    }

    override var debugDescription: String {
        var descriptionBuilder = DebugDescriptionBuilder(baseDescription: super.debugDescription)
        descriptionBuilder.add(key: "group", value: group)
        descriptionBuilder.add(key: "state", value: state)
        descriptionBuilder.add(key: "title", value: title)
        descriptionBuilder.add(key: "bookmarks", value: bookmarks)
        return descriptionBuilder.description
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(group)
        hasher.combine(title)
        hasher.combine(bookmarks)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let groupData = object as? BookmarkSectionData else {
            return false
        }

        return group == groupData.group && title == groupData.title && bookmarks == groupData.bookmarks
    }
}

// MARK: - BookmarkSectionController

final class BookmarkSectionController: ListSectionController, SwipeCollectionViewCellDelegate {
    var groupData: BookmarkSectionData?
    private let formatters: Formatters

    public init(formatters: Formatters) {
        self.formatters = formatters
        super.init()
    }

    public override func sizeForItem(at index: Int) -> CGSize {
        return CGSize(width: collectionContext!.containerSize.width, height: 40.0)
    }

    public override func numberOfItems() -> Int {
        guard let groupData = groupData else {
            return 0
        }

        if hasTitleRow {
            if groupData.state == .closed {
                return 1
            }
            else {
                return groupData.bookmarks.count + 1
            }
        }
        else {
            return groupData.bookmarks.count
        }
    }

    private func cellClass(for bookmark: Bookmark) -> UICollectionViewCell.Type {
        if bookmark.isTripBookmark {
            return TripBookmarkTableCell.self
        }
        else {
            return StopBookmarkTableCell.self
        }
    }

    public override func cellForItem(at index: Int) -> UICollectionViewCell {
        if hasTitleRow && index == 0 {
            return titleCell(at: index)
        }
        else {
            return bookmarkCell(at: index)
        }
    }

    private func titleCell(at index: Int) -> UICollectionViewCell {
        guard
            let groupData = groupData,
            let cell = collectionContext?.dequeueReusableCell(of: CollapsibleHeaderCell.self, for: self, at: index) as? CollapsibleHeaderCell
        else {
            fatalError()
        }

        cell.textLabel.text = groupData.title
        cell.state = groupData.state

        return cell

    }

    private func bookmarkCell(at index: Int) -> UICollectionViewCell {
        guard let bookmarkArrivalData = bookmark(at: index) else {
            fatalError()
        }

        let klass = cellClass(for: bookmarkArrivalData.bookmark)
        if let cell = collectionContext?.dequeueReusableCell(of: klass, for: self, at: index) as? TripBookmarkTableCell {
            cell.delegate = self
            cell.formatters = formatters
            cell.data = bookmarkArrivalData
            return cell
        }
        else if let cell = collectionContext?.dequeueReusableCell(of: klass, for: self, at: index) as? StopBookmarkTableCell {
            cell.data = bookmarkArrivalData.bookmark
            return cell
        }
        else {
            fatalError()
        }
    }

    public override func didUpdate(to object: Any) {
        precondition(object is BookmarkSectionData)
        groupData = object as? BookmarkSectionData
    }

    public override func didSelectItem(at index: Int) {
        if hasTitleRow && index == 0 {
            guard let groupData = groupData else { return }
            groupData.toggled(groupData, groupData.state.toggledValue())
            return
        }

        guard let bookmark = bookmark(at: index) else { return }
        bookmark.selected(bookmark.bookmark)
    }

    // MARK: - Index Path Management

    private var hasTitleRow: Bool {
        groupData?.title != nil
    }

    private func bookmark(at index: Int) -> BookmarkArrivalData? {
        if hasTitleRow {
            return groupData?.bookmarks[index - 1]
        }
        else {
            return groupData?.bookmarks[index]
        }
    }

    // MARK: - SwipeCollectionViewCellDelegate

    func collectionView(_ collectionView: UICollectionView, editActionsForItemAt indexPath: IndexPath, for orientation: SwipeActionsOrientation) -> [SwipeAction]? {
        guard
            orientation == .right,
            let bookmark = bookmark(at: indexPath.item)
        else {
            return nil
        }

        let edit = SwipeAction(style: .default, title: Strings.edit) { _, _ in
            bookmark.edited(bookmark.bookmark)
        }

        let delete = SwipeAction(style: .destructive, title: Strings.delete) { _, _ in
            bookmark.deleted(bookmark.bookmark)
        }

        return [delete, edit]
    }

    // MARK: - Private

    private func userHeaderView(atIndex index: Int) -> UICollectionReusableView {
        guard let view = collectionContext?.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, for: self, class: TableSectionHeaderView.self, at: index) as? TableSectionHeaderView else {
            fatalError()
        }

        view.textLabel.text = groupData?.title
        return view
    }
}

final class CollapsibleHeaderCell: SelfSizingCollectionCell {

    private let kUseDebugColors = false

    let textLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        return label
    }()

    private lazy var stateImageView: UIImageView = {
        let imageView = UIImageView(image: Icons.chevron)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        return imageView
    }()

    var state: BookmarkSectionState = .closed {
        didSet {
            if state == .open {
                stateImageView.transform = CGAffineTransform(rotationAngle: .pi / 2.0)
            }
            else {
                stateImageView.transform = CGAffineTransform(rotationAngle: 0.0)
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = ThemeColors.shared.systemFill

        let imageWrapper = stateImageView.embedInWrapperView(setConstraints: false)
        NSLayoutConstraint.activate([
            stateImageView.centerYAnchor.constraint(equalTo: imageWrapper.centerYAnchor),
            stateImageView.heightAnchor.constraint(equalToConstant: 12.0),
            imageWrapper.widthAnchor.constraint(equalToConstant: 12.0),
            stateImageView.leadingAnchor.constraint(equalTo: imageWrapper.leadingAnchor),
            stateImageView.trailingAnchor.constraint(equalTo: imageWrapper.trailingAnchor)
        ])

        let stack = UIStackView.horizontalStack(arrangedSubviews: [imageWrapper, textLabel])
        stack.spacing = ThemeMetrics.padding
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -ThemeMetrics.compactPadding),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),

            contentView.heightAnchor.constraint(greaterThanOrEqualTo: stack.heightAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40.0)
        ])

        if kUseDebugColors {
            contentView.backgroundColor = .red
            textLabel.backgroundColor = .green
            stateImageView.backgroundColor = .blue
            imageWrapper.backgroundColor = .purple
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class TripBookmarkTableCell: SwipeCollectionViewCell, SelfSizing, Separated {
    var data: BookmarkArrivalData? {
        didSet {
            guard let data = data else { return }

            stopArrivalView.title = data.bookmark.name
            stopArrivalView.arrivalDepartures = data.arrivalDepartures
        }
    }

    var arrivalDeparture: ArrivalDeparture? {
        didSet {
            guard let arrivalDeparture = arrivalDeparture else { return }
            stopArrivalView.arrivalDeparture = arrivalDeparture
        }
    }

    private var stopArrivalView: StopArrivalView!

    public var formatters: Formatters! {
        didSet {
            if stopArrivalView == nil {
                stopArrivalView = StopArrivalView.autolayoutNew()
                stopArrivalView.formatters = formatters
                stopArrivalView.showDisclosureIndicator = false
                contentView.addSubview(stopArrivalView)

                NSLayoutConstraint.activate([
                    stopArrivalView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
                    stopArrivalView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
                    stopArrivalView.topAnchor.constraint(equalTo: contentView.topAnchor),
                    stopArrivalView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
                ])
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        fixiOS13AutoLayoutBug()

        contentView.backgroundColor = ThemeColors.shared.systemBackground
        contentView.layer.addSublayer(separator)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Separator

    let separator = tableCellSeparatorLayer()

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSeparator()
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        return calculateLayoutAttributesFitting(layoutAttributes)
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        stopArrivalView.prepareForReuse()
    }
}

final class StopBookmarkTableCell: SwipeCollectionViewCell, SelfSizing, Separated {
    var data: Bookmark? {
        didSet {
            guard let data = data else { return }
            label.text = data.name
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        label.text = nil
    }

    let label = UILabel.autolayoutNew()

    override init(frame: CGRect) {
        super.init(frame: frame)

        fixiOS13AutoLayoutBug()

        contentView.layer.addSublayer(separator)

        contentView.addSubview(label)
        label.pinToSuperview(.layoutMargins)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Separator

    let separator = tableCellSeparatorLayer()

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSeparator()
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        return calculateLayoutAttributesFitting(layoutAttributes)
    }
}
