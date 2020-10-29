//
//  OBAListView.swift
//  OBAKit
//
//  Created by Alan Chu on 9/30/20.
//

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
public class OBAListView: UICollectionView, UICollectionViewDelegate, SwipeCollectionViewCellDelegate, OBAListRowHeaderSupplementaryViewDelegate {

    /// The view type for `EmptyData`.
    /// To use the standard view, provide the view model. OBAListView will handle the view lifecycle.
    /// If you use a custom view, you are responsible for managing it.
    public enum EmptyData {
        case standard(StandardEmptyDataViewModel)
        case custom(UIView)
    }

    weak public var obaDataSource: OBAListViewDataSource?
    weak public var collapsibleSectionsDelegate: OBAListViewCollapsibleSectionsDelegate?

    fileprivate var diffableDataSource: UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem>!

    /// Cache EmptyDataSetView if we need to reuse it during fast updates.
    fileprivate var standardEmptyDataView: EmptyDataSetView?

    public init() {
        super.init(frame: .zero, collectionViewLayout: UICollectionViewLayout())            // Load dummy layout first...
        self.collectionViewLayout = createLayout()                                          // Then, load real layout because we need to reference self.
        self.diffableDataSource = createDataSource()
        self.dataSource = diffableDataSource
        self.delegate = self

        self.backgroundColor = .systemBackground

        // Register default rows.
        self.register(reuseIdentifierProviding: OBAListRowCell<OBAListRowViewDefault>.self)
        self.register(reuseIdentifierProviding: OBAListRowCell<OBAListRowViewSubtitle>.self)
        self.register(reuseIdentifierProviding: OBAListRowCell<OBAListRowViewValue>.self)
        self.register(reuseIdentifierProviding: OBAListRowCell<OBAListRowViewHeader>.self)

        self.register(OBAListRowHeaderSupplementaryView.self,
                      forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                      withReuseIdentifier: OBAListRowHeaderSupplementaryView.ReuseIdentifier)
        self.register(OBAListViewSeparatorSupplementaryView.self,
                      forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
                      withReuseIdentifier: OBAListViewSeparatorSupplementaryView.ReuseIdentifier)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Data source

    fileprivate func createDataSource() -> UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem> {
        let dataSource = UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem>(collectionView: self) { (collectionView, indexPath, item) -> UICollectionViewCell? in
            let config = item.contentConfiguration
            let reuseIdentifier = config.obaContentView.ReuseIdentifier
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath)

            guard let obaView = cell as? OBAListViewCell else {
                fatalError("You are trying to use a cell in OBAListView that isn't OBAListViewCell.")
            }

            obaView.delegate = self
            obaView.apply(config)

            return obaView
        }

        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            if kind == UICollectionView.elementKindSectionHeader {
                return self.headerView(collectionView: collectionView, of: kind, at: indexPath, dataSource: dataSource)
            } else if kind == UICollectionView.elementKindSectionFooter {
                return self.footerView(collectionView: collectionView, of: kind, at: indexPath, dataSource: dataSource)
            } else {
                return nil
            }
        }

        return dataSource
    }

    // MARK: - Supplementary views
    fileprivate func headerView(
        collectionView: UICollectionView,
        of kind: String,
        at indexPath: IndexPath,
        dataSource: UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem>
    ) -> UICollectionReusableView? {
        guard kind == UICollectionView.elementKindSectionHeader,
              let view = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: OBAListRowHeaderSupplementaryView.ReuseIdentifier,
                for: indexPath) as? OBAListRowHeaderSupplementaryView
        else { return nil }

        let section = dataSource.snapshot().sectionIdentifiers[indexPath.section]
        view.delegate = self
        view.section = section

        return view
    }

    fileprivate func footerView(
        collectionView: UICollectionView,
        of kind: String,
        at indexPath: IndexPath,
        dataSource: UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem>
    ) -> UICollectionReusableView? {
        return collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: OBAListViewSeparatorSupplementaryView.ReuseIdentifier, for: indexPath)
    }

    // MARK: - Delegate methods
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = diffableDataSource.itemIdentifier(for: indexPath) else { return }
        item.onSelectAction?(item)
    }

    public func collectionView(_ collectionView: UICollectionView, editActionsForItemAt indexPath: IndexPath, for orientation: SwipeActionsOrientation) -> [SwipeAction]? {
        guard collectionView == self else { return nil }
        guard let item = self.diffableDataSource.itemIdentifier(for: indexPath) else { return nil }

        // The action closure passes a copy of the view model, so we need to include that.
        func setItem(on action: OBAListViewContextualAction<AnyOBAListViewItem>) -> OBAListViewContextualAction<AnyOBAListViewItem> {
            var newAction = action
            newAction.item = item
            return newAction
        }

        switch orientation {
        case .left:
            return item.leadingContextualActions?.map { setItem(on: $0).swipeAction }
        case .right:
            return item.trailingContextualActions?.map { setItem(on: $0).swipeAction }
        }
    }

    // MARK: - Layout configuration
    fileprivate func createLayout() -> UICollectionViewLayout {
        return UICollectionViewCompositionalLayout { section, _ -> NSCollectionLayoutSection? in
            return self.diffableDataSource.snapshot().sectionIdentifiers[section].sectionLayout
        }
    }

    // MARK: - Data source
    public func applyData(animated: Bool = false) {
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

        var snapshot = NSDiffableDataSourceSnapshot<OBAListViewSection, AnyOBAListViewItem>()
        snapshot.appendSections(sections)
        for section in sections {
            // If the section is collapsible, account for its state.
            // Otherwise, show all items.
            if let collapsedState = section.collapseState {
                switch collapsedState {
                case .collapsed:
                    snapshot.deleteItems(section.contents)
                case .expanded:
                    snapshot.appendItems(section.contents, toSection: section)
                }
            } else {
                snapshot.appendItems(section.contents, toSection: section)
            }
        }

        DispatchQueue.main.async {
            self.diffableDataSource.apply(snapshot, animatingDifferences: animated)
        }
    }

    fileprivate func emptyDataConfiguration(isEmpty: Bool) {
        guard isEmpty, let emptyData = self.obaDataSource?.emptyData(for: self) else {
            self.backgroundView?.isHidden = true
            return
        }

        self.backgroundView?.removeFromSuperview()
        self.backgroundView = nil

        let view: UIView
        switch emptyData {
        case .standard(let viewModel):
            let emptyDataView: EmptyDataSetView
            if let existing = self.standardEmptyDataView,
               existing.alignment == viewModel.alignment {
                emptyDataView = existing
            } else {
                emptyDataView = EmptyDataSetView(alignment: viewModel.alignment)
            }

            emptyDataView.apply(viewModel)

            self.standardEmptyDataView = emptyDataView

            view = emptyDataView
        case .custom(let custom):
            custom.translatesAutoresizingMaskIntoConstraints = true
            view = custom
        }

        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.backgroundView = view
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

    public func didTap(_ headerView: OBAListRowViewHeader, section: OBAListViewSection) {
        collapsibleSectionsDelegate?.didTap(self, headerView: headerView, section: section)
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
