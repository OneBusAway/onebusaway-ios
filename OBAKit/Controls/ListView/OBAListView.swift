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
    func didTap(_ headerView: OBAListRowHeaderSupplementaryView, section: OBAListViewSection)
}

/// Displays information as a vertical-scrolling list, a la TableView.
///
/// There are two separate `OBAListViewConfigurator`s under-the-hood. One is for iOS 14+, the other
/// is for iOS 13.  iOS 14 uses `UICollectionLayoutListConfiguration` because its user experience
/// is much better than our custom table view-like implementation. The purpose of `OBAList` is to abstract
/// this platform-specific code away from the rest of the application.
///
/// This architecture prepares us for the deprecation of our custom implementation when we drop iOS 13.
///
/// There are a number of "bridging" models that mimic iOS 14 functionality for iOS 13. See the `Bridge`
/// subfolder for examples.
public class OBAListView: UICollectionView, OBAListRowHeaderSupplementaryViewDelegate {
    weak var obaDataSource: OBAListViewDataSource?
    weak var obaDelegate: OBAListViewDelegate?
    fileprivate var diffableDataSource: UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem>!

    public init() {
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
        let layout = UICollectionViewCompositionalLayout(section: section)

        super.init(frame: .zero, collectionViewLayout: layout)

        self.diffableDataSource = createDataSource()
        self.dataSource = diffableDataSource

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

    // MARK: - DATA SOURCE
    public func applyData() {
        var snapshot = NSDiffableDataSourceSnapshot<OBAListViewSection, AnyOBAListViewItem>()
        let sections = self.obaDataSource?.items(for: self) ?? []

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

    public func didTap(_ headerView: OBAListRowHeaderSupplementaryView, section: OBAListViewSection) {
        obaDelegate?.didTap(headerView, section: section)
        print("tapped \(section)")
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
    var name: String
    var address: String

    var contentConfiguration: OBAContentConfiguration {
        return OBAListContentConfiguration(image: UIImage(systemName: "person.fill"), text: name, secondaryText: address, appearance: .subtitle, accessoryType: .none)
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
