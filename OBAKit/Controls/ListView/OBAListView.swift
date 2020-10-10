//
//  OBAListView.swift
//  OBAKit
//
//  Created by Alan Chu on 9/30/20.
//

import SwipeCellKit

protocol OBAListViewDataSource: class {
    func items(for listView: OBAListView) -> [OBAListViewSection]
}

protocol OBAListViewDelegate: class {
    func didSelect(_ listView: OBAListView, item: AnyOBAListViewItem)
    func didTap(_ headerView: OBAListRowCellHeader, section: OBAListViewSection)
}

/// Displays information as a vertical-scrolling list, a la TableView.
///
/// To set data in the List View, call `applyData()`. To supply data, conform to `OBAListViewDataSource`.
/// `applyData()` calls `OBAListViewDataSource.items(:_)`.
public class OBAListView: UICollectionView, UICollectionViewDelegate, SwipeCollectionViewCellDelegate, OBAListRowHeaderSupplementaryViewDelegate {
    weak var obaDataSource: OBAListViewDataSource?
    weak var obaDelegate: OBAListViewDelegate?
    fileprivate var diffableDataSource: UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem>!

    public init() {
        super.init(frame: .zero, collectionViewLayout: OBAListView.createLayout())

        self.diffableDataSource = createDataSource()
        self.dataSource = diffableDataSource
        self.delegate = self

        self.backgroundColor = .systemBackground

        // Register default rows.
        self.register(reuseIdentifierProviding: OBAListRowCell<OBAListRowCellDefault>.self)
        self.register(reuseIdentifierProviding: OBAListRowCell<OBAListRowCellSubtitle>.self)
        self.register(reuseIdentifierProviding: OBAListRowCell<OBAListRowCellValue>.self)
        self.register(reuseIdentifierProviding: OBAListRowCell<OBAListRowCellHeader>.self)

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

    func createDataSource() -> UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem> {
        let dataSource = UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem>(collectionView: self) {
            (collectionView, indexPath, item) -> UICollectionViewCell? in
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
    func headerView(collectionView: UICollectionView,
                    of kind: String,
                    at indexPath: IndexPath,
                    dataSource: UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem>)
    -> UICollectionReusableView? {
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

    func footerView(collectionView: UICollectionView,
                    of kind: String,
                    at indexPath: IndexPath,
                    dataSource: UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem>)
    -> UICollectionReusableView? {
        guard kind == UICollectionView.elementKindSectionFooter,
              let view = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: OBAListViewSeparatorSupplementaryView.ReuseIdentifier,
                for: indexPath) as? OBAListViewSeparatorSupplementaryView
        else { return nil }

        return view
    }


    // MARK: - Delegate methods
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = diffableDataSource.itemIdentifier(for: indexPath) else { return }

        if let _ = item.as(OBAListViewSectionHeader.self) {
            guard let cell = collectionView.cellForItem(at: indexPath) as? OBAListRowCell<OBAListRowCellHeader> else { return }
            self.obaDelegate?.didTap(cell.listRowView, section: diffableDataSource.snapshot().sectionIdentifiers[indexPath.section])
        } else {
            self.obaDelegate?.didSelect(self, item: item)
        }
    }

    public func collectionView(_ collectionView: UICollectionView, editActionsForItemAt indexPath: IndexPath, for orientation: SwipeActionsOrientation) -> [SwipeAction]? {
        guard collectionView == self else { return nil }
        guard let item = self.diffableDataSource.itemIdentifier(for: indexPath) else { return nil }

        switch orientation {
        case .left:
            return item.leadingSwipeActions?.map { $0.swipeAction }
        case .right:
            return item.trailingSwipeActions?.map { $0.swipeAction }
        }
    }

    // MARK: - Layout configuration
    static func createLayout() -> UICollectionViewLayout {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44))
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitem: item, count: 1)
        let section = NSCollectionLayoutSection(group: group)

        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(40)
        )
        let sectionHeader = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        sectionHeader.pinToVisibleBounds = true

        let footerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(2)
        )
        let sectionFooter = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: footerSize,
            elementKind: UICollectionView.elementKindSectionFooter,
            alignment: .bottom
        )
        sectionFooter.pinToVisibleBounds = false

        section.boundarySupplementaryItems = [sectionHeader, sectionFooter]

        let layout = UICollectionViewCompositionalLayout(section: section)
        return layout
    }

    // MARK: - Data source
    public func applyData() {
        let sections = self.obaDataSource?.items(for: self) ?? []
        var snapshot = NSDiffableDataSourceSnapshot<OBAListViewSection, AnyOBAListViewItem>()
        snapshot.appendSections(sections)
        for section in sections {
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
            self.diffableDataSource.apply(snapshot)
        }
    }

    // MARK: - Helpers
    func register(reuseIdentifierProviding view: ReuseIdentifierProviding.Type) {
        self.register(view, forCellWithReuseIdentifier: view.ReuseIdentifier)
    }

    func register<Item: OBAListViewItem>(listViewItem: Item.Type) {
        guard let cellType = listViewItem.customCellType else {
            Logger.warn("You asked OBAListView to register \(String(describing: listViewItem)), but it doesn't have a customCellType.")
            return
        }

        self.register(reuseIdentifierProviding: cellType)
    }

    public func didTap(_ headerView: OBAListRowCellHeader, section: OBAListViewSection) {
        obaDelegate?.didTap(headerView, section: section)
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

private struct Person: OBAListViewItem {
    var id: UUID = UUID()
    var name: String
    var address: String

    var contentConfiguration: OBAContentConfiguration {
        return OBAListContentConfiguration(image: UIImage(systemName: "person.fill"), text: name, secondaryText: address, appearance: .subtitle, accessoryType: .none)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
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
                Person(name: "Bo", address: "123 Main St"),
                Person(name: "Bob", address: "456 Broadway"),
                Person(name: "Bobby", address: "asdfasdkfjad")
            ]),
            OBAListViewSection(id: "2", title: "C", contents: [
                Person(name: "Ca", address: "193 Lochmere Ln"),
                Person(name: "Cab", address: "anywhere u want"),
                Person(name: "Cabby", address: "huh")
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
