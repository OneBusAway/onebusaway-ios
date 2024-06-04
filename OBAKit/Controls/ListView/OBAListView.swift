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

    /// The delegate of this list view.
    weak public var obaDelegate: OBAListViewDelegate?

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
        if (obaDataSource?.items(for: self) ?? [])[indexPath.section].hasHeader,
           indexPath.row == 0 {
            cell.accessibilityTraits = .header
        }

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
        let cell = collectionView.dequeueConfiguredReusableCell(using: listCellRegistration, for: indexPath, item: item)
        if (obaDataSource?.items(for: self) ?? [])[indexPath.section].hasHeader,
           indexPath.row == 0 {
            cell.accessibilityTraits = .header
        }
        return cell
    }

    // MARK: - Item selection actions
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        var correctedItemIndex = indexPath.item
        if lastDataSourceSnapshot[indexPath.section].hasHeader {
            // If index path is zero, the user selected the header item.
            // dataSource.sectionSnapshotHandler will handle notifying the
            // collapsibleSectionDelegate of a collapsing section.
            guard indexPath.item != 0 else { return }
            correctedItemIndex -= 1
        }

        let item = lastDataSourceSnapshot[indexPath.section][correctedItemIndex]
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
    public func applyData(animated: Bool = true) {
        var sections = self.obaDataSource?.items(for: self) ?? []
        self.emptyDataConfiguration(isEmpty: sections.isEmpty)

        if let collapsibleDelegate = self.collapsibleSectionsDelegate {
            // Add collapsed state to the section, if it is allowed to collapse.
            sections = sections.map { section in
                var newSection = section
                if collapsibleDelegate.canCollapseSection(self, section: section) {
                    newSection.collapseState = collapsibleDelegate.collapsedSections.contains(newSection.id) ? .collapsed : .expanded
                } else {
                    newSection.collapseState = nil
                }
                return newSection
            }
        }

        self.lastDataSourceSnapshot = sections

        var snapshot = NSDiffableDataSourceSnapshot<SectionType, ItemType>()
        snapshot.appendSections(sections)
        diffableDataSource.apply(snapshot, animatingDifferences: false)

        for section in sections {
            var sectionSnapshot = NSDiffableDataSourceSectionSnapshot<ItemType>()

            if section.hasHeader {
                let header = OBAListViewHeader(id: section.id, title: section.title, isCollapsible: section.collapseState != nil).typeErased

                // If the section is collapsible, attach contents to the header item.
                // Otherwise, treat both header item and contents as equals.
                //
                // This was an attempt to fix #421 -- OBAListView DiffableDataSource can't find item index of headers,
                // it is a partial fix because only BookmarksViewController has this problem now.
                // Related: https://stackoverflow.com/q/64089384
                if let collapsedState = section.collapseState {
                    sectionSnapshot.append([header])
                    sectionSnapshot.append(section.contents, to: header)
                    switch collapsedState {
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

            diffableDataSource.apply(sectionSnapshot, to: section, animatingDifferences: false)
        }

        self.obaDelegate?.didApplyData(self)
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
