//
//  OBAListView.swift
//  OBAKit
//
//  Created by Alan Chu on 9/30/20.
//

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
public class OBAListView: UICollectionView, UICollectionViewDelegate, OBAListRowHeaderSupplementaryViewDelegate {
    weak var obaDataSource: OBAListViewDataSource?
    weak var obaDelegate: OBAListViewDelegate?
    fileprivate var diffableDataSource: UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem>!

    fileprivate let usingFallbackLayout: Bool

    public init(usingFallbackLayout fallbackLayout: Bool = false) {
        self.usingFallbackLayout = fallbackLayout

        let layout: UICollectionViewLayout
        if #available(iOS 14, *) {
            if fallbackLayout {
                layout = OBAListView.createCustomLayout()
            } else {
                layout = OBAListView.createListLayout()
            }
        } else {
            layout = OBAListView.createCustomLayout()
        }

        super.init(frame: .zero, collectionViewLayout: layout)

        self.diffableDataSource = createDataSource()
        self.dataSource = diffableDataSource
        self.delegate = self

        self.backgroundColor = .systemBackground

        // Register default rows.
        self.register(reuseIdentifierProviding: OBAListViewCell<OBAListRowCellDefault>.self)
        self.register(reuseIdentifierProviding: OBAListViewCell<OBAListRowCellSubtitle>.self)
        self.register(reuseIdentifierProviding: OBAListViewCell<OBAListRowCellValue>.self)
        self.register(reuseIdentifierProviding: OBAListViewCell<OBAListRowCellHeader>.self)

        self.register(OBAListRowHeaderSupplementaryView.self,
                      forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                      withReuseIdentifier: OBAListRowHeaderSupplementaryView.ReuseIdentifier)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func createDataSource() -> UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem> {
        let dataSource = UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem>(collectionView: self) {
            (collectionView, indexPath, item) -> UICollectionViewCell? in
            let config = item.contentConfiguration
            let reuseIdentifier = config.obaContentView.ReuseIdentifier
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath)

            guard let obaView = cell as? (UICollectionViewCell & OBAContentView) else {
                fatalError("You are trying to use a cell in OBAListView that doesn't conform to OBAContentView.")
            }

            obaView.apply(config)

            return obaView
        }

        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
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

        return dataSource
    }

    // MARK: - CELL REGISTRATION
    func register(reuseIdentifierProviding view: ReuseIdentifierProviding.Type) {
        self.register(view, forCellWithReuseIdentifier: view.ReuseIdentifier)
    }

    // MARK: - Delegate methods
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = diffableDataSource.itemIdentifier(for: indexPath) else { return }

        if let _ = item.as(OBAListViewSectionHeader.self) {
            guard let cell = collectionView.cellForItem(at: indexPath) as? OBAListViewCell<OBAListRowCellHeader> else { return }
            self.obaDelegate?.didTap(cell.listRowView, section: diffableDataSource.snapshot().sectionIdentifiers[indexPath.section])
        } else {
            self.obaDelegate?.didSelect(self, item: item)
        }
    }

    // MARK: - Layout configuration

    @available(iOS 14, *)
    static func createListLayout() -> UICollectionViewLayout {
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.headerMode = .firstItemInSection
        config.showsSeparators = false
        return UICollectionViewCompositionalLayout.list(using: config)
    }

    @available(iOS, deprecated: 14, renamed: "createListLayout")
    static func createCustomLayout() -> UICollectionViewLayout {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44))
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitem: item, count: 1)
        let section = NSCollectionLayoutSection(group: group)

        let headerFooterSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(40)
        )
        let sectionHeader = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerFooterSize,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        sectionHeader.pinToVisibleBounds = true
        section.boundarySupplementaryItems = [sectionHeader]
        section.visibleItemsInvalidationHandler = { (visibleItems, scrollOffset, layoutEnvironment) in
            print(visibleItems)
        }

        let layout = UICollectionViewCompositionalLayout(section: section)
        return layout
    }


    // MARK: - Data source

    public func applyData() {
        let sections = self.obaDataSource?.items(for: self) ?? []
        if #available(iOS 14, *) {
            if usingFallbackLayout {
                self.applyDataUsingFallback(sections: sections)
            } else {
                self.applyDataUsingSectionSnapshot(sections: sections)
            }
        } else {
            self.applyDataUsingFallback(sections: sections)
        }
    }

    // MARK: Platform specific
    @available(iOS 14, *)
    private func applyDataUsingSectionSnapshot(sections: [OBAListViewSection]) {
        for section in sections {
            var sectionSnapshot = NSDiffableDataSourceSectionSnapshot<AnyOBAListViewItem>()
            if let sectionHeader = section.listViewSectionHeader {
                sectionSnapshot.append([sectionHeader])
                sectionSnapshot.append(section.contents, to: sectionHeader)

                if let collapsedState = section.collapseState {
                    switch collapsedState {
                    case .collapsed:
                        sectionSnapshot.collapse([sectionHeader])
                    case .expanded:
                        sectionSnapshot.expand([sectionHeader])
                    }
                }
            } else {
                sectionSnapshot.append(section.contents)
            }

            diffableDataSource.apply(sectionSnapshot, to: section)
        }
    }

    @available(iOS, deprecated: 14, renamed: "applyDataUsingSectionSnapshot")
    private func applyDataUsingFallback(sections: [OBAListViewSection]) {
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

        self.diffableDataSource.apply(snapshot)
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
    private static let personsListView = PersonsListView(fallbackLayout: false)
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
    var name: String
    var address: String

    var contentConfiguration: OBAContentConfiguration {
        return OBAListContentConfiguration(image: UIImage(systemName: "person.fill"), text: name, secondaryText: address, appearance: .subtitle, accessoryType: .none)
    }
}

private class PersonsListView: OBAListView, OBAListViewDataSource {
    init(fallbackLayout: Bool) {
        super.init(usingFallbackLayout: fallbackLayout)
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
