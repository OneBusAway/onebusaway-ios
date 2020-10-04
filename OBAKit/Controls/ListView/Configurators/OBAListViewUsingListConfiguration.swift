//
//  OBAListViewUsingListConfiguration.swift
//  OBAKit
//
//  Created by Alan Chu on 10/2/20.
//

@available(iOS 14, *)
struct OBAListViewUsingListConfiguration: OBAListViewConfigurator {
    func createLayout() -> UICollectionViewLayout {
        return UICollectionViewCompositionalLayout { section, layoutEnvironment in
            var config = UICollectionLayoutListConfiguration(appearance: .plain)
            config.headerMode = .firstItemInSection
            config.showsSeparators = false
            return NSCollectionLayoutSection.list(using: config, layoutEnvironment: layoutEnvironment)
        }
    }

    func registerCells(_ listView: OBAListView) {
        listView.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: UICollectionViewListCell.ReuseIdentifier)
    }

    func createDataSource(_ listView: OBAListView) -> UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem> {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, AnyOBAListViewItem> { (cell, indexPath, item) in
            cell.contentConfiguration = item.listViewConfigurationForThisItem(listView).listContentConfiguration
        }

        return UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem>(collectionView: listView, cellProvider: {
            (collectionView, indexPath, item) -> UICollectionViewCell? in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        })
    }
}
