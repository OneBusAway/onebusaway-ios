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
import OBAKitCore

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
        collectionView.isScrollEnabled = true
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.directionalLayoutMargins = ThemeMetrics.collectionViewLayoutMargins

        return collectionView
    }()

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(collectionView)
        collectionView.pinToSuperview(.edges)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        registerKeyboardNotifications()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        unregisterKeyboardNotifications()
    }

    // MARK: - Public Methods

    /// Reloads the collection controller's underlying `listAdapter`
    /// - Parameter animated: Animate the reload or not.
    public func reload(animated: Bool) {
        listAdapter.performUpdates(animated: animated)
    }

    // MARK: - Keyboard

    private func registerKeyboardNotifications() {
        application.notificationCenter.addObserver(self, selector: #selector(keyboardWasShown(_:)), name: UIResponder.keyboardDidShowNotification, object: nil)
        application.notificationCenter.addObserver(self, selector: #selector(keyboardWillBeHidden(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    private func unregisterKeyboardNotifications() {
        application.notificationCenter.removeObserver(self, name: UIResponder.keyboardDidShowNotification, object: nil)
        application.notificationCenter.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWasShown(_ notification: Notification) {
        guard let kbRect = notification.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect else {
            return
        }

        let contentInsets = UIEdgeInsets(top: collectionView.contentInset.top, left: 0, bottom: kbRect.height, right: 0)
        collectionView.contentInset = contentInsets
        collectionView.scrollIndicatorInsets = contentInsets
    }

    @objc private func keyboardWillBeHidden(_ notification: Notification) {
        collectionView.contentInset = UIEdgeInsets(top: collectionView.contentInset.top, left: 0, bottom: 0, right: 0)
        collectionView.scrollIndicatorInsets = collectionView.contentInset
    }
}

public protocol ListProvider: ListAdapterDataSource {
    var collectionController: CollectionController { get }
}
