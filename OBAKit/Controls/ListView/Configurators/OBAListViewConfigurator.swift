//
//  OBAListViewConfigurator.swift
//  OBAKit
//
//  Created by Alan Chu on 10/2/20.
//

protocol OBAListViewConfigurator {
    func createLayout() -> UICollectionViewLayout

    func registerCells(_ listView: OBAListView)
    func createDataSource(_ listView: OBAListView) -> UICollectionViewDiffableDataSource<OBAListViewSection, AnyOBAListViewItem>

}
