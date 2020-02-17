//
//  TodayViewController.swift
//  TodayView
//
//  Created by Aaron Brethorst on 10/13/19.
//

import UIKit
import NotificationCenter
import OBAKitCore
import CoreLocation
import IGListKit

class TodayViewController: UIViewController, NCWidgetProviding, BookmarkDataDelegate, ListAdapterDataSource {

    // MARK: - App Context

    private let userDefaults = UserDefaults(suiteName: Bundle.main.appGroup!)!
    private lazy var locationManager = CLLocationManager()
    private lazy var locationService = LocationService(userDefaults: userDefaults, locationManager: locationManager)

    private lazy var app: CoreApplication = {
        let bundledRegions = Bundle.main.path(forResource: "regions", ofType: "json")!
        let config = CoreAppConfig(appBundle: Bundle.main, userDefaults: userDefaults, bundledRegionsFilePath: bundledRegions)
        return CoreApplication(config: config)
    }()

    // MARK: - Bookmarks

    private lazy var dataLoader = BookmarkDataLoader(application: app, delegate: self)

    func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader) {
        adapter.performUpdates(animated: false)
    }

    private var bestAvailableBookmarks: [Bookmark] {
        var bookmarks = app.userDataStore.favoritedBookmarks
        if bookmarks.count == 0 {
            bookmarks = app.userDataStore.bookmarks
        }
        return bookmarks
    }

    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        adapter.collectionView = collectionView
        adapter.dataSource = self

        view.addSubview(collectionView)
        collectionView.pinToSuperview(.edges)

        // Enables the 'Show More' button in the widget interface
        extensionContext?.widgetLargestAvailableDisplayMode = .expanded

        dataLoader.loadData()
    }

    // MARK: - NotificationCenter

    func widgetActiveDisplayModeDidChange(_ activeDisplayMode: NCWidgetDisplayMode, withMaximumSize maxSize: CGSize) {
        switch activeDisplayMode {
        case .compact:
            // The compact view is a fixed size.
            preferredContentSize = maxSize
        case .expanded:
            let height = CGFloat(bestAvailableBookmarks.count) * 55.0
            preferredContentSize = CGSize(width: maxSize.width, height: min(height, maxSize.height))
        @unknown default:
            preconditionFailure("Unexpected value for activeDisplayMode.")
        }
    }

    func widgetPerformUpdate(completionHandler: @escaping (NCUpdateResult) -> Void) {
        dataLoader.loadData()
        completionHandler(.newData)
    }

    // MARK: - List Kit

    lazy var adapter: ListAdapter = {
        return ListAdapter(updater: ListAdapterUpdater(), viewController: self)
    }()

    let collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: CGRect.zero, collectionViewLayout: UICollectionViewFlowLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        return collectionView
    }()

    // MARK: - Bookmark Actions

    private func didSelectBookmark(_ bookmark: Bookmark) {
        let router = URLSchemeRouter(scheme: Bundle.main.extensionURLScheme!)
        let url = router.encode(stopID: bookmark.stopID, regionID: bookmark.regionIdentifier)
        extensionContext!.open(url, completionHandler: nil)
    }

    // MARK: ListAdapterDataSource

    func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        return bestAvailableBookmarks.compactMap { bm -> BookmarkArrivalData? in
            var arrDeps = [ArrivalDeparture]()

            if let key = TripBookmarkKey(bookmark: bm) {
                arrDeps = dataLoader.dataForKey(key)
            }

            return BookmarkArrivalData(bookmark: bm, arrivalDepartures: arrDeps, selected: didSelectBookmark(_:))
        }
    }

    func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        return TodaySectionController(formatters: app.formatters)
    }

    func emptyView(for listAdapter: ListAdapter) -> UIView? {
        let emptyView = EmptyDataSetView(alignment: .top)
        emptyView.titleLabel.text = Strings.emptyBookmarkTitle
        emptyView.titleLabel.font = UIFont.preferredFont(forTextStyle: .title2).bold
        emptyView.bodyLabel.text = Strings.emptyBookmarkBody
        return emptyView
    }
}

final class TodaySectionController: ListSectionController {

    private var object: BookmarkArrivalData?
    private let formatters: Formatters

    init(formatters: Formatters) {
        self.formatters = formatters
        super.init()
    }

    override func sizeForItem(at index: Int) -> CGSize {
        return CGSize(width: collectionContext!.containerSize.width, height: 55)
    }

    override func cellForItem(at index: Int) -> UICollectionViewCell {
        guard
            let context = collectionContext,
            let cell = context.dequeueReusableCell(of: TodayArrivalCell.self, for: self, at: index) as? TodayArrivalCell,
            let object = object
        else {
            fatalError()
        }

        cell.setData(bookmarkArrivalData: object, formatters: formatters)

        return cell
    }

    override func didSelectItem(at index: Int) {
        guard let object = object else { return }
        object.selected(object.bookmark)
    }

    public override func didUpdate(to object: Any) {
        precondition(object is BookmarkArrivalData)
        self.object = object as? BookmarkArrivalData
    }
}
