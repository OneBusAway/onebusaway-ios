//
//  OBAListView.swift
//  OBAKit
//
//  Created by Alan Chu on 9/30/20.
//

import OBAKitCore
import UIKit

/// Displays information as a vertical-scrolling list, a la TableView.
///
/// ## Providing Data
/// Data is provided via `obaDataSource.items(:_)`.Then, apply the data using `applyData()`.
///
/// ## Custom cells
/// Default cells are available for use without additional configuration, however you'll need to register other
/// custom cells that your list may use. Use `register(listViewItem: _)` to ensure that the cells
/// you register has an `OBAListViewItem` view model and has a custom `OBAListViewCell` type.
///
/// A requirement of OBAListView is that cells must be an `OBAListViewCell`.
///
/// ## Collapsible Sections
/// To support collapsible sections, set `collapsibleSectionsDelegate`. The delegate will allow you
/// to specify which sections can collapse and respond to collapse/expand actions.
///
/// ## Context Menus
/// To support context menus, set `contextMenuDelegate`. The delegate will allow you to provide menu
/// actions based on the selected item. For more info, refer to `OBAListViewMenuActions`.
public class OBAListView: UICollectionView, UICollectionViewDelegate {

    /// The view type for `EmptyData`.
    /// To use the standard view, provide the view model. OBAListView will handle the view lifecycle.
    /// If you use a custom view, you are responsible for managing it.
    public enum EmptyData {
        case standard(StandardEmptyDataViewModel)
        case custom(UIView)
    }

    public var formatters: Formatters?

    // MARK: - Features (delegates)
    /// The source of truth for this list view.
    weak public var obaDataSource: OBAListViewDataSource?

    /// Optional. Implement `OBAListViewCollapsibleSectionsDelegate` to add support for collapsible sections for this list view.
    weak public var collapsibleSectionsDelegate: OBAListViewCollapsibleSectionsDelegate?

    /// Optional. Implement `OBAListViewContextMenuDelegate` to add support for context menus for this list view.
    weak public var contextMenuDelegate: OBAListViewContextMenuDelegate?

    // MARK: - Private properties
    fileprivate typealias SectionType = OBAListViewSection
    fileprivate typealias ItemType = AnyOBAListViewItem

    fileprivate var diffableDataSource: UICollectionViewDiffableDataSource<SectionType, ItemType>!

    /// Cache the last applied data source snapshot, as we cannot rely on the parent data source to ensure
    /// that the data source and the UI are sync'd. This is the source of truth of this list view.
    fileprivate var lastDataSourceSnapshot: [OBAListViewSection] = []

    /// Cache the last used context menu for handling "perform preview action".
    fileprivate var lastUsedContextMenu: (identifier: String, actions: OBAListViewMenuActions)?

    /// Cache EmptyDataSetView if we need to reuse it during fast updates.
    fileprivate lazy var standardEmptyDataView: EmptyDataSetView = EmptyDataSetView()

    public init() {
        super.init(frame: .zero, collectionViewLayout: UICollectionViewLayout())            // Load dummy layout first...
        self.collectionViewLayout = createLayout()                                          // Then, load real layout because we need to reference self.
        self.diffableDataSource = createDataSource()
        self.dataSource = diffableDataSource
        self.delegate = self

        self.backgroundColor = .systemBackground
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Data source

    fileprivate func createDataSource() -> UICollectionViewDiffableDataSource<SectionType, ItemType> {
        let dataSource = UICollectionViewDiffableDataSource<SectionType, ItemType>(collectionView: self) { [unowned self] (collectionView, indexPath, item) -> UICollectionViewCell? in

            switch item.configuration {
            case .custom(let config):
                if let listConfig = config as? OBAListRowConfiguration {
                    return self.listCell(collectionView, indexPath: indexPath, item: item, config: listConfig.listConfiguration, accessories: [listConfig.accessoryType.cellAccessory])
                } else {
                    return self.standardCell(collectionView, indexPath: indexPath, item: item, config: config)
                }
            case .list(let config, let accessories):
                return self.listCell(collectionView, indexPath: indexPath, item: item, config: config, accessories: accessories)
            }
        }

        dataSource.sectionSnapshotHandlers.shouldCollapseItem = { [unowned self] item in self.canCollapseOrExpandSection(item) }
        dataSource.sectionSnapshotHandlers.shouldExpandItem   = { [unowned self] item in self.canCollapseOrExpandSection(item) }

        dataSource.sectionSnapshotHandlers.willCollapseItem = { [unowned self] item in self.notifyDelegateOfCollapsingOrExpandingSection(item) }
        dataSource.sectionSnapshotHandlers.willExpandItem   = { [unowned self] item in self.notifyDelegateOfCollapsingOrExpandingSection(item) }

        return dataSource
    }

    func standardCell(_ collectionView: UICollectionView, indexPath: IndexPath, item: AnyOBAListViewItem, config: OBAContentConfiguration) -> UICollectionViewCell? {
        // Reference the formatters in the item's content configuration
        var formattedConfig = config
        formattedConfig.formatters = self.formatters

        let reuseIdentifier = formattedConfig.obaContentView.ReuseIdentifier
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath)

        guard let obaView = cell as? OBAListViewCell else {
            fatalError("You are trying to use a cell in OBAListView that isn't OBAListViewCell.")
        }

        obaView.apply(formattedConfig)

        return obaView
    }

    let listCellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, AnyOBAListViewItem> { cell, _, item in
        let config = item.configuration
        switch config {
        case .list(let contentConfig, let accessories):
            cell.contentConfiguration = contentConfig
            cell.accessories = accessories.compactMap { $0 }
        case .custom(let config):
            if let listRow = config as? OBAListRowConfiguration {
                cell.contentConfiguration = listRow.listConfiguration
                if let accessory = listRow.accessoryType.cellAccessory {
                    cell.accessories = [accessory]
                } else {
                    cell.accessories = []
                }
            }
        }
    }

    func listCell(_ collectionView: UICollectionView, indexPath: IndexPath, item: AnyOBAListViewItem, config: UIListContentConfiguration, accessories: [UICellAccessory?]) -> UICollectionViewListCell? {
        return collectionView.dequeueConfiguredReusableCell(using: listCellRegistration, for: indexPath, item: item)
    }

    // MARK: - Item selection actions
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.section < lastDataSourceSnapshot.count else {
            Logger.warn("didSelectItemAt: section index \(indexPath.section) out of bounds")
            return
        }

        var correctedItemIndex = indexPath.item
        if lastDataSourceSnapshot[indexPath.section].hasHeader {
            // If index path is zero, the user selected the header item.
            // dataSource.sectionSnapshotHandler will handle notifying the
            // collapsibleSectionDelegate of a collapsing section.
            guard indexPath.item != 0 else { return }
            correctedItemIndex -= 1
        }

        guard let item = lastDataSourceSnapshot[indexPath.section][correctedItemIndex] else { return }
        item.onSelectAction?(item)

        // Fixes #399 -- List view cells appears selected after presenting/pushing view controller
        // This shouldn't be necessary and is a duct tape fix.
        // Supporting native cell behavior is ideal, where the cell remains
        // highlighted until after the view controller is popped off the stack.
        // I suspect that OBAListView should be a UICollectionViewController
        // instead of a UICollectionView for this to work elegantly.
        collectionView.deselectItem(at: indexPath, animated: true)
    }

    // MARK: - Section collapse configuration
    fileprivate func canCollapseOrExpandSection(_ item: AnyOBAListViewItem) -> Bool {
        guard let header = item.as(OBAListViewHeader.self),
              let section = self.lastDataSourceSnapshot.first(where: { $0.id == header.id }) else { return false }
        return self.collapsibleSectionsDelegate?.canCollapseSection(self, section: section) ?? false
    }

    fileprivate func notifyDelegateOfCollapsingOrExpandingSection(_ item: AnyOBAListViewItem) {
        guard let header = item.as(OBAListViewHeader.self),
              let section = self.lastDataSourceSnapshot.first(where: { $0.id == header.id }) else { return }
        self.collapsibleSectionsDelegate?.didTap(self, section: section)
    }

    // MARK: - Context menu configuration
    public func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = itemForIndexPath(indexPath),
              let config = self.contextMenuDelegate?.contextMenu(self, for: item) else { return nil }

        // Add uuid so in `willPerformPreviewActionForMenuWith`, we can independently
        // verify (without using index paths that may change) that the user did
        // intend to perform on this specific menu.
        let id = UUID().uuidString
        self.lastUsedContextMenu = (id, config)
        return config.contextMenuConfiguration(identifier: id)
    }

    public func collectionView(_ collectionView: UICollectionView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        guard let menuAction = self.lastUsedContextMenu, menuAction.identifier == configuration.identifier as? String else { return }
        animator.addCompletion {
            menuAction.actions.performPreviewAction?()
        }
    }

    /// Accounts for whether the section has a header or not.
    func itemForIndexPath(_ indexPath: IndexPath) -> AnyOBAListViewItem? {
        guard indexPath.section < lastDataSourceSnapshot.count else {
            Logger.warn("itemForIndexPath: section index \(indexPath.section) out of bounds")
            return nil
        }

        var correctedItemIndex = indexPath.item

        if lastDataSourceSnapshot[indexPath.section].hasHeader {
            guard correctedItemIndex != 0 else { return nil }
            correctedItemIndex -= 1
        }

        return lastDataSourceSnapshot[indexPath.section][correctedItemIndex]
    }

    // MARK: - Layout configuration
    fileprivate func createLayout() -> UICollectionViewLayout {
        return UICollectionViewCompositionalLayout { [unowned self] section, environment -> NSCollectionLayoutSection? in
            guard section < self.lastDataSourceSnapshot.count else {
                Logger.warn("createLayout: section index \(section) out of bounds")
                return nil
            }
            let sectionModel = self.lastDataSourceSnapshot[section]

            var configuration = sectionModel.configuration.listConfiguration()
            configuration.headerMode = sectionModel.hasHeader ? .firstItemInSection : .none

            configuration.separatorConfiguration = .init(listAppearance: .insetGrouped)
            configuration.itemSeparatorHandler = { [unowned self] (indexPath, listConfiguration) -> UIListSeparatorConfiguration in
                guard let item = self.itemForIndexPath(indexPath) else { return listConfiguration }

                var configuration = listConfiguration
                configuration.applying(item.separatorConfiguration)
                return configuration
            }

            configuration.leadingSwipeActionsConfigurationProvider = { [unowned self] indexPath -> UISwipeActionsConfiguration? in
                leadingSwipeActions(for: indexPath)
            }

            configuration.trailingSwipeActionsConfigurationProvider = { [unowned self] indexPath -> UISwipeActionsConfiguration? in
                trailingSwipeActions(for: indexPath)
            }

            return NSCollectionLayoutSection.readableContentGuideList(using: configuration, layoutEnvironment: environment)
        }
    }

    fileprivate func leadingSwipeActions(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let actions = itemForIndexPath(indexPath)?.leadingContextualActions else { return nil }

        let config = UISwipeActionsConfiguration(actions: actions.map { $0.contextualAction })
        config.performsFirstActionWithFullSwipe = false

        return config
    }

    fileprivate func trailingSwipeActions(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let item = itemForIndexPath(indexPath) else { return nil }
        let contextualActions = item.trailingContextualActions ?? []
        var swipeActions = contextualActions.map { $0.contextualAction }

        if let deleteAction = item.onDeleteAction {
            // Hides "Delete" text if the cell is less than 64 units tall.
            let cellSize = self.cellForItem(at: indexPath)?.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height ?? 0
            let isCellCompact = cellSize < 64
            let swipeActionText = isCellCompact ? nil : Strings.delete

            let deleteAction =  UIContextualAction(style: .destructive, title: swipeActionText) { _, _, success in
                deleteAction(item)
                success(true)
            }
            deleteAction.image = Icons.delete

            swipeActions.append(deleteAction)
        }

        let config = UISwipeActionsConfiguration(actions: swipeActions)
        config.performsFirstActionWithFullSwipe = false

        return config
    }

    // MARK: - Data source
    public func applyData(animated: Bool = false, scrollBehavior: ScrollBehavior = .preserve) {
        var sections = self.obaDataSource?.items(for: self) ?? []

        if sections.isEmpty {
            handleEmptyDataSource()
            emptyDataConfiguration(isEmpty: true)
            return
        }

        sections = handleEmptySections(sections: sections)

        // After filtering out headerless empty sections, the result may also be empty.
        if sections.isEmpty {
            handleEmptyDataSource()
            emptyDataConfiguration(isEmpty: true)
            return
        }

        guard validateSnapshot(sections) else { return }

        applyDataSmartly(to: sections, animated: animated, scrollBehavior: scrollBehavior)
    }

    fileprivate func emptyDataConfiguration(isEmpty: Bool) {
        self.backgroundView?.removeFromSuperview()
        self.backgroundView?.isHidden = false
        self.backgroundView = nil

        guard isEmpty, let emptyData = self.obaDataSource?.emptyData(for: self) else {
            return
        }

        let view: UIView
        switch emptyData {
        case .standard(let viewModel):
            self.standardEmptyDataView.apply(viewModel)
            view = self.standardEmptyDataView
        case .custom(let custom):
            custom.translatesAutoresizingMaskIntoConstraints = true
            view = custom
        }

        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.backgroundView = view
    }

    // MARK: - Delegate
    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? OBAListViewCell)?.willDisplayCell(in: self)
    }

    // MARK: - Helpers
    func register(reuseIdentifierProviding view: ReuseIdentifierProviding.Type) {
        self.register(view, forCellWithReuseIdentifier: view.ReuseIdentifier)
    }

    /// Registers a custom cell type as defined by the view model.
    /// - Parameter listViewItem: The view model with a custom cell to register.
    public func register<Item: OBAListViewItem>(listViewItem: Item.Type) {
        guard let cellType = listViewItem.customCellType else {
            Logger.warn("You asked OBAListView to register \(String(describing: listViewItem)), but it doesn't have a customCellType.")
            return
        }

        self.register(reuseIdentifierProviding: cellType)
    }

    public func scrollTo(section: OBAListViewSection, at position: UICollectionView.ScrollPosition, animated: Bool) {
        let sectionIdentifiers = diffableDataSource.snapshot().sectionIdentifiers
        guard let matchingSection = sectionIdentifiers.first(where: { $0.id == section.id }),
              let lastItemOfSection = matchingSection.contents.last,
              let indexPath = diffableDataSource.indexPath(for: lastItemOfSection) else { return }

        self.scrollToItem(at: indexPath, at: position, animated: animated)
    }

    /// Index path of the last item in the last section currently applied to the data source.
    /// Queries the live snapshot rather than `lastDataSourceSnapshot` so the result reflects
    /// any section-snapshot updates already applied during the same `applyData` pass.
    private var lastItemIndexPath: IndexPath? {
        let snapshot = diffableDataSource.snapshot()
        guard let lastSection = snapshot.sectionIdentifiers.last else { return nil }
        let items = snapshot.itemIdentifiers(inSection: lastSection)
        guard let lastItem = items.last,
              let indexPath = diffableDataSource.indexPath(for: lastItem) else { return nil }
        return indexPath
    }
}

// MARK: - Smart Apply / Reloading

extension OBAListView {

    enum UpdateStrategy {

        case fullRebuild

        case sectionReload

        case noChange

    }

    private func applyDataSmartly(to newSections: [OBAListViewSection], animated: Bool = false, scrollBehavior: ScrollBehavior = .preserve) {
        let scrollState = ScrollState(from: self, behavior: scrollBehavior)

        var newSections = newSections
        self.emptyDataConfiguration(isEmpty: newSections.isEmpty)

        if let collapsibleDelegate = self.collapsibleSectionsDelegate {
            newSections = applyCollapseState(to: newSections, with: collapsibleDelegate)
        }

        let strategy = getUpdateStrategy(oldSections: self.lastDataSourceSnapshot, newSections: newSections)

        self.lastDataSourceSnapshot = newSections

        // `diffableDataSource.apply` is asynchronous when the collection view is
        // on screen, so the snapshot read by `lastItemIndexPath` is only accurate
        // once the final section-snapshot apply completes. Restore scroll state
        // in that completion so `.scrollToBottom` targets the new last item, not
        // the pre-apply one.
        applyUpdate(with: strategy, to: newSections, animated: animated) {
            scrollState.restore(for: strategy)
        }
    }

    private func applyCollapseState(
        to sections: [OBAListViewSection],
        with collapsibleDelegate: OBAListViewCollapsibleSectionsDelegate
    ) -> [OBAListViewSection] {
        return sections.map { section in
            var updatedSection = section

            if collapsibleDelegate.canCollapseSection(self, section: section) {
                updatedSection.collapseState = collapsibleDelegate.collapsedSections.contains(section.id) ? .collapsed : .expanded
            } else {
                updatedSection.collapseState = nil
            }

            return updatedSection
        }
    }

    func getUpdateStrategy(
        oldSections: [OBAListViewSection],
        newSections: [OBAListViewSection]
    ) -> UpdateStrategy {

        guard !oldSections.isEmpty, !newSections.isEmpty else {
            return oldSections.isEmpty && newSections.isEmpty ? .noChange : .fullRebuild
        }

        guard oldSections.map(\.id) == newSections.map(\.id) else {
            return .fullRebuild
        }

        for (oldSection, newSection) in zip(oldSections, newSections) {

            if oldSection.hasHeader != newSection.hasHeader ||
                oldSection.collapseState != newSection.collapseState ||
                oldSection.contents != newSection.contents {
                return .sectionReload
            }
        }

        return .noChange
    }

    private func applyUpdate(
        with strategy: UpdateStrategy,
        to newSections: [OBAListViewSection],
        animated: Bool,
        completion: @escaping () -> Void
    ) {
        switch strategy {
        case .noChange:
            completion()

        case .fullRebuild:
            applyFullRebuild(newSections: newSections, animated: animated, completion: completion)

        case .sectionReload:
            applySectionReload(newSections: newSections, animated: animated, completion: completion)
        }
    }

    private func applyFullRebuild(newSections: [OBAListViewSection], animated: Bool, completion: @escaping () -> Void) {
        var snapshot = NSDiffableDataSourceSnapshot<SectionType, ItemType>()
        snapshot.appendSections(newSections)

        diffableDataSource.apply(snapshot, animatingDifferences: animated)

        applySectionSnapshots(newSections.map { ($0, nil) }, completion: completion)
    }

    private func applySectionReload(newSections: [OBAListViewSection], animated: Bool, completion: @escaping () -> Void) {
        var snapshot = diffableDataSource.snapshot()

        // Map existing section identifiers by id so we can target the identifiers in the snapshot
        let existingSections = snapshot.sectionIdentifiers
        let existingById: [String: SectionType] = Dictionary(uniqueKeysWithValues: existingSections.map { ($0.id, $0) })

        let pairs: [(existing: SectionType, new: OBAListViewSection)] = newSections.compactMap { newSection in
            guard let existing = existingById[newSection.id] else { return nil }
            return (existing, newSection)
        }

        if pairs.isEmpty {
            // The live snapshot has diverged from `lastDataSourceSnapshot` — log so this desync is observable.
            Logger.warn("applySectionReload: no section identifiers matched live snapshot; falling back to full rebuild.")
            applyFullRebuild(newSections: newSections, animated: animated, completion: completion)
            return
        }

        snapshot.reloadSections(pairs.map { $0.existing })

        diffableDataSource.apply(snapshot, animatingDifferences: animated)

        // Apply new content snapshots to the existing section identifiers
        applySectionSnapshots(pairs.map { ($0.new, $0.existing) }, completion: completion)
    }

    /// Enqueues a section-snapshot apply for each entry and attaches `completion` to the
    /// last one. `UICollectionViewDiffableDataSource` serializes apply calls on the same
    /// data source, so the last apply's completion fires after all earlier ones have
    /// flushed — which is the synchronization point we need for scroll restoration,
    /// since `diffableDataSource.snapshot()` only reflects the newly-added items once
    /// the queued applies have drained.
    private func applySectionSnapshots(
        _ sections: [(new: OBAListViewSection, applyingTo: OBAListViewSection?)],
        completion: @escaping () -> Void
    ) {
        guard !sections.isEmpty else {
            completion()
            return
        }

        for (index, section) in sections.enumerated() {
            let isLast = index == sections.count - 1
            applySectionSnapshot(
                for: section.new,
                applyingTo: section.applyingTo,
                animatingDifferences: false,
                completion: isLast ? completion : nil
            )
        }
    }

    private func applySectionSnapshot(
        for section: OBAListViewSection,
        applyingTo targetSection: OBAListViewSection? = nil,
        animatingDifferences: Bool,
        completion: (() -> Void)? = nil
    ) {
        var sectionSnapshot = NSDiffableDataSourceSectionSnapshot<ItemType>()

        if section.hasHeader {
            let header = OBAListViewHeader(
                id: section.id,
                title: section.title,
                isCollapsible: section.collapseState != nil
            ).typeErased

            if let collapseState = section.collapseState {
                sectionSnapshot.append([header])
                sectionSnapshot.append(section.contents, to: header)

                switch collapseState {
                case .collapsed:
                    sectionSnapshot.collapse([header])
                case .expanded:
                    sectionSnapshot.expand([header])
                }
            } else {
                sectionSnapshot.append([header])
                sectionSnapshot.append(section.contents)
            }
        } else {
            sectionSnapshot.append(section.contents)
        }

        let sectionToApply = targetSection ?? section
        diffableDataSource.apply(sectionSnapshot, to: sectionToApply, animatingDifferences: animatingDifferences, completion: completion)
    }

}

// MARK: - Edge Case Handling

extension OBAListView {

    /// Validates that the data source snapshot is consistent. Surfaces the offending IDs so the
    /// upstream data defect can be diagnosed instead of silently dropping the update.
    private func validateSnapshot(_ sections: [OBAListViewSection]) -> Bool {
        let sectionIDs = sections.map { $0.id }
        let duplicateSectionIDs = duplicates(in: sectionIDs)
        guard duplicateSectionIDs.isEmpty else {
            Logger.error("Invalid snapshot: duplicate section IDs \(duplicateSectionIDs); skipping update.")
            return false
        }

        for section in sections {
            let itemIDs = section.contents.map { $0.id }
            let duplicateItemIDs = duplicates(in: itemIDs)
            guard duplicateItemIDs.isEmpty else {
                Logger.error("Invalid snapshot: duplicate item IDs \(duplicateItemIDs) in section '\(section.id)'; skipping update.")
                return false
            }
        }

        return true
    }

    private func duplicates<T: Hashable>(in values: [T]) -> [T] {
        var seen: Set<T> = []
        var dupes: [T] = []
        for value in values where !seen.insert(value).inserted {
            dupes.append(value)
        }
        return dupes
    }

    /// Handles edge case where data source returns nil or empty
    private func handleEmptyDataSource() {
        let snapshot = NSDiffableDataSourceSnapshot<SectionType, ItemType>()
        diffableDataSource.apply(snapshot, animatingDifferences: false)
        self.lastDataSourceSnapshot = []
    }

    /// Handles edge case where sections contain no items
    private func handleEmptySections(sections: [OBAListViewSection]) -> [OBAListViewSection] {
        return sections.filter { section in
            return section.hasHeader || !section.contents.isEmpty
        }
    }
}

extension OBAListView {

    public enum ScrollBehavior {
        case preserve
        case scrollToBottom
    }

    private struct ScrollState {
        let offset: CGPoint
        let isUserScrolling: Bool
        let behavior: ScrollBehavior
        weak var listView: OBAListView?

        init(from listView: OBAListView, behavior: ScrollBehavior) {
            self.offset = listView.contentOffset
            self.isUserScrolling = listView.isTracking || listView.isDecelerating
            self.behavior = behavior
            self.listView = listView
        }

        func restore(for strategy: UpdateStrategy) {
            switch behavior {
            case .preserve:
                // Don't fight a finger drag. `.scrollToBottom` is an explicit
                // caller intent (e.g. Load More) and bypasses this guard below.
                guard !isUserScrolling else { return }
                guard strategy != .fullRebuild, strategy != .noChange else { return }
                DispatchQueue.main.async { [weak listView, offset] in
                    guard let listView else { return }
                    // Force the post-apply layout pass so `contentSize` reflects
                    // the new item heights before we clamp the restored offset.
                    // Without this the clamp can run against the pre-apply size.
                    listView.layoutIfNeeded()
                    let maxY = max(0, listView.contentSize.height - listView.bounds.height + listView.contentInset.bottom)
                    let safeOffset = CGPoint(x: offset.x, y: min(offset.y, maxY))
                    listView.setContentOffset(safeOffset, animated: false)
                }

            case .scrollToBottom:
                // Skip scrolling when nothing actually changed.
                guard strategy != .noChange else { return }
                DispatchQueue.main.async { [weak listView] in
                    guard let listView, let indexPath = listView.lastItemIndexPath else { return }
                    // Compositional layout sizes cells lazily, so a single
                    // scrollToItem against a distant last item lands against
                    // estimated heights and falls short of the real bottom.
                    // First snap (no animation) to provoke the layout pass that
                    // measures the cells we'd scroll past, then re-scroll
                    // against the now-accurate heights to land exactly at the
                    // last item.
                    listView.layoutIfNeeded()
                    listView.scrollToItem(at: indexPath, at: .bottom, animated: false)
                    listView.layoutIfNeeded()
                    listView.scrollToItem(at: indexPath, at: .bottom, animated: true)
                }
            }
        }
    }

}

// MARK: - Preview
#if DEBUG
import SwiftUI
import OBAKitCore

struct OBAListView_Previews: PreviewProvider {
    private static let personsListView = PersonsListView()
    static var previews: some View {
        Group {
            UIViewPreview {
                personsListView
            }
            .onAppear { personsListView.applyData() }
        }
    }
}

private class PersonsListView: OBAListView, OBAListViewDataSource {
    override init() {
        super.init()
        self.obaDataSource = self
        self.register(reuseIdentifierProviding: DEBUG_CustomContentCell.self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func items(for listView: OBAListView) -> [OBAListViewSection] {
        return [
            OBAListViewSection(id: "1", title: "B", contents: [
                DEBUG_Person(name: "Bo", address: "123 Main St"),
                DEBUG_Person(name: "Bob", address: "456 Broadway"),
                DEBUG_Person(name: "Bobby", address: "asdfasdkfjad")
            ]),
            OBAListViewSection(id: "2", title: "C", contents: [
                DEBUG_Person(name: "Ca", address: "193 Lochmere Ln"),
                DEBUG_Person(name: "Cab", address: "anywhere u want"),
                DEBUG_Person(name: "Cabby", address: "huh")
            ]),
            OBAListViewSection(id: "3", title: "Custom Content", contents: [
                DEBUG_CustomContent(text: "Item A"),
                DEBUG_CustomContent(text: "Item Bee"),
                DEBUG_CustomContent(text: "Item See")
            ])
        ]
    }
}
#endif
