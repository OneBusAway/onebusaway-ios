//
//  BookmarksViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/26/19.
//

import UIKit
import AloeStackView
import CoreLocation
import OBAKitCore

/// This view controller powers the Bookmarks tab.
@objc(OBABookmarksViewController)
public class BookmarksViewController: UIViewController,
    AloeStackTableBuilder,
    LocationServiceDelegate,
    ManageBookmarksDelegate,
    ModalDelegate {

    /// The OBA application object
    private let application: Application

    lazy var stackView = AloeStackView.autolayoutNew(
        backgroundColor: ThemeColors.shared.systemBackground
    )

    // MARK: - Init

    /// Creates a Bookmarks controller
    /// - Parameter application: The OBA application object
    public init(application: Application) {
        self.application = application

        super.init(nibName: nil, bundle: nil)

        title = OBALoc("bookmarks_controller.title", value: "Bookmarks", comment: "Title of the Bookmarks tab")
        tabBarItem.image = Icons.bookmarksTabIcon

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: OBALoc("bookmarks_controller.groups_button_title", value: "Edit", comment: "Groups button title in Bookmarks controller"), style: .plain, target: self, action: #selector(manageGroups))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        cancelUpdates()
    }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(stackView)
        stackView.pinToSuperview(.edges)

        loadData()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadTable()

        application.notificationCenter.addObserver(self, selector: #selector(applicationEnteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)

        application.locationService.addDelegate(self)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        application.notificationCenter.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        application.locationService.removeDelegate(self)

        timer?.invalidate()
    }

    // MARK: - Notifications

    @objc private func applicationEnteredBackground(note: Notification) {
        cancelUpdates()
    }

    // MARK: - Location Service Delegate

    @objc public func locationService(_ service: LocationService, locationChanged location: CLLocation) {
        // rearrange based on distance perhaps?
    }

    // MARK: - UI Loading

    private func reloadTable() {
        stackView.removeAllRows()
        tripBookmarkViewMap.removeAll()

        let groups = application.userDataStore.bookmarkGroups

        for group in groups {
            let bookmarks = application.userDataStore.bookmarksInGroup(group)
            addRowsForGroup(name: group.name, bookmarks: bookmarks)
        }

        // Only show a title on the 'ungrouped' list if groups have been defined.
        let uncategorizedTitle = groups.count == 0 ? nil : self.title

        addRowsForGroup(name: uncategorizedTitle, bookmarks: application.userDataStore.bookmarksInGroup(nil))
    }

    private func addRowsForGroup(name: String?, bookmarks: [Bookmark]) {
        if let name = name {
            addGroupedTableHeaderToStack(headerText: name)
        }

        for b in bookmarks {
            let view: UIView

            if let key = TripBookmarkKey(bookmark: b) {
                let arrivalView = StopArrivalView.autolayoutNew()
                arrivalView.formatters = application.formatters
                arrivalView.showDisclosureIndicator = true
                arrivalView.routeHeadsignLabel.text = key.bookmarkName
                arrivalView.showLoadingIndicator()
                tripBookmarkViewMap[key] = arrivalView
                view = arrivalView
                loadData(key: key)
            }
            else {
                view = DefaultTableRowView(title: b.name, accessoryType: .disclosureIndicator)
            }

            addGroupedTableRowToStack(view) { [weak self] _ in
                guard let self = self else { return }
                self.application.viewRouter.navigateTo(stop: b.stop, from: self)
            }
            stackView.setInset(forRow: view, inset: UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10))
        }
    }

    // MARK: - Trip Bookmark Data

    /// A dictionary that maps each trip bookmark key to a stop arrival view
    /// This is used to update the UI when new `ArrivalDeparture` objects are loaded.
    private var tripBookmarkViewMap = [TripBookmarkKey: StopArrivalView]()

    /// A list of unique stop IDs that are represented by the `tripBookmarkViewMap`.
    ///
    /// In other words, this represents the full list of stops that must be loaded
    /// to populate all of the trip bookmarks.
    private var tripBookmarkStopIDs: [String] {
        Array(Set(tripBookmarkViewMap.keys.map {$0.stopID}))
    }

    // MARK: - Refreshing

    private var timer: Timer?

    private func startRefreshTimer() {
        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.loadData()
        }
    }

    // MARK: - Data Loading

    private var operations = [Operation]()

    private func loadData() {
        cancelUpdates()
        for key in tripBookmarkViewMap.keys {
            loadData(key: key)
        }
        startRefreshTimer()
    }

    private func loadData(key: TripBookmarkKey) {
        guard
            let modelService = application.restAPIModelService
        else {
            return
        }

        let op = modelService.getArrivalsAndDeparturesForStop(id: key.stopID, minutesBefore: 0, minutesAfter: 60)
        op.then { [weak self] in
            guard
                let self = self,
                let keysAndDeps = op.stopArrivals?.arrivalsAndDepartures.tripKeyGroupedElements
            else {
                return
            }

            for (key, deps) in keysAndDeps {
                let view = self.tripBookmarkViewMap[key]
                view?.hideLoadingIndicator()
                view?.arrivalDepartures = deps
            }
        }
        operations.append(op)
    }

    private func cancelUpdates() {
        timer?.invalidate()

        for op in operations {
            op.cancel()
        }
    }

    // MARK: - Bookmark Groups

    @objc private func manageGroups() {
        let manageGroupsController = ManageBookmarksAndGroupsViewController(application: application, delegate: self)
        let navigation = UINavigationController(rootViewController: manageGroupsController)
        application.viewRouter.present(navigation, from: self)
    }

    // MARK: - ModalDelegate

    public func dismissModalController(_ controller: UIViewController) {
        controller.dismiss(animated: true, completion: nil)
    }

    // MARK: - ManageBookmarksDelegate

    func manageBookmarksReloadData(_ controller: ManageBookmarksAndGroupsViewController) {
        reloadTable()
    }
}

// MARK: - Private Helpers

/// Provides a way to group `ArrivalDeparture`s by the data elements used in trip bookmarks.
fileprivate struct TripBookmarkKey: Hashable, Equatable {
    let stopID: String
    let routeShortName: String
    let routeID: RouteID
    let tripHeadsign: String
    let bookmarkName: String?

    init?(bookmark: Bookmark) {
        guard
            let routeShortName = bookmark.routeShortName,
            let routeID = bookmark.routeID,
            let tripHeadsign = bookmark.tripHeadsign
        else {
            return nil
        }
        self.stopID = bookmark.stopID
        self.routeShortName = routeShortName
        self.routeID = routeID
        self.tripHeadsign = tripHeadsign
        self.bookmarkName = bookmark.name
    }

    init(arrivalDeparture: ArrivalDeparture) {
        self.stopID = arrivalDeparture.stopID
        self.routeShortName = arrivalDeparture.routeShortName
        self.routeID = arrivalDeparture.routeID
        self.tripHeadsign = arrivalDeparture.tripHeadsign
        self.bookmarkName = nil
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        return
            lhs.stopID == rhs.stopID &&
            lhs.routeShortName == rhs.routeShortName &&
            lhs.routeID == rhs.routeID &&
            lhs.tripHeadsign == rhs.tripHeadsign
    }
}

fileprivate extension Sequence where Element == ArrivalDeparture {
    /// Creates a mapping of `TripBookmarkKey`s to `ArrivalDeparture`s so that
    /// it is easier to load data and inject `ArrivalDeparture` objects into `StopArrivalView`s.
    /// - Note: Also sorts the list of `ArrivalDeparture`s.
    var tripKeyGroupedElements: [TripBookmarkKey: [ArrivalDeparture]] {
        var keysAndDeps = [TripBookmarkKey: [ArrivalDeparture]]()

        for arrDep in self {
            let key = TripBookmarkKey(arrivalDeparture: arrDep)

            var departures = keysAndDeps[key, default: [ArrivalDeparture]()]
            departures.append(arrDep)
            keysAndDeps[key] = departures.sorted { $0.arrivalDepartureDate < $1.arrivalDepartureDate }
        }

        return keysAndDeps
    }
}
