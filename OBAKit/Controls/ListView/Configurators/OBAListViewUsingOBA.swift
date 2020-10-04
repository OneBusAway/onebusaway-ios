//
//  OBAListViewUsingOBA.swift
//  OBAKit
//
//  Created by Alan Chu on 10/2/20.
//

import Foundation

@available(iOS, deprecated: 14, renamed: "OBAListViewUsingListConfiguration")
struct OBAListViewUsingOBA: OBAListViewConfigurator {
    func createLayout() -> UICollectionViewLayout {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44))
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitem: item, count: 1)
        let section = NSCollectionLayoutSection(group: group)
        return UICollectionViewCompositionalLayout(section: section)
    }

    func registerCells(_ listView: OBAListView) {
        listView.register(OBAListViewRow.self, forCellWithReuseIdentifier: OBAListViewRow.ReuseIdentifier)
    }

    func createDataSource(_ listView: OBAListView) -> UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem> {
        return UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem>(collectionView: listView) { (collectionView, indexPath, item) -> UICollectionViewCell? in
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: OBAListViewRow.ReuseIdentifier, for: indexPath) as? OBAListViewRow else { return nil }
            cell.configure(with: item.listViewConfigurationForThisItem(listView))
            return cell
        }
    }
}
