//
//  OBACellRegistration.swift
//  OBAKit
//
//  Created by Alan Chu on 10/2/20.
//

import UIKit

struct OBACellRegistration<Cell, Item> where Cell: UICollectionViewCell {
    typealias Handler = (Cell, IndexPath, Item) -> Void

    var handler: Handler

    @available(iOS 14, *)
    var collectionViewCellRegistration: UICollectionView.CellRegistration<Cell, Item> {
        return UICollectionView.CellRegistration(handler: handler)
    }

    init(handler: @escaping Handler) {
        self.handler = handler
    }
}
