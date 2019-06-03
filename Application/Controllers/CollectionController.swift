//
//  CollectionController.swift
//  OBANext
//
//  Created by Aaron Brethorst on 1/13/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit
import FloatingPanel
import IGListKit

public class CollectionController: UIViewController {
    private let application: Application

    public let listAdapter: ListAdapter

    public init(application: Application, dataSource: UIViewController & ListAdapterDataSource) {
        self.application = application
        self.listAdapter = ListAdapter(updater: ListAdapterUpdater(), viewController: dataSource, workingRangeSize: 1)

        super.init(nibName: nil, bundle: nil)

        self.listAdapter.collectionView = collectionView
        self.listAdapter.dataSource = dataSource
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public lazy var collectionViewLayout: UICollectionViewLayout = {
        let layout = UICollectionViewFlowLayout()
        layout.estimatedItemSize = CGSize(width: 375, height: 40)
        layout.itemSize = UICollectionViewFlowLayout.automaticSize
        return layout
    }()

    public lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionViewLayout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.isScrollEnabled = false
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.alwaysBounceVertical = true
        collectionView.directionalLayoutMargins = ThemeMetrics.collectionViewLayoutMargins

        return collectionView
    }()

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(collectionView)
        collectionView.pinToSuperview(.edges)
    }
}

@objc public protocol ListProvider: ListAdapterDataSource {
    var collectionController: CollectionController { get }
}
