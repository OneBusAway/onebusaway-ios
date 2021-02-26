//
//  StopViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import CoreLocation

// swiftlint:disable file_length

/// This is the core view controller for displaying information about a transit stop.
///
/// Specifically, `StopViewController` provides you with information about upcoming
/// arrivals and departures at this stop, along with the ability to create push
/// notification 'alarms' and bookmarks, view information about the location of a
/// particular vehicle, and report problems with a trip.
public class StopViewController: UIViewController,
    AlarmBuilderDelegate,
    AppContext,
    BookmarkEditorDelegate,
    Idleable,
    OBAListViewDataSource,
    OBAListViewContextMenuDelegate,
    OBAListViewCollapsibleSectionsDelegate,
    ModalDelegate,
    Previewable,
    StopPreferencesDelegate {

    /// The available sections in this view controller.
    enum ListSections {
        case stopHeader
        case emptyData
        case serviceAlerts
        case hiddenRoutesToggle
        case arrivalDepartures(suffix: String)
        case loadMoreButton
        case moreOptions

        var sectionID: String {
            switch self {
            case .arrivalDepartures(let suffix):
                return "section_arrival_departures_\(suffix)"
            default:
                return "section_\(self)"
            }
        }
    }

    public let application: Application

    let stopID: StopID

    public var bookmarkContext: Bookmark?

    let minutesBefore: UInt = 5
    static let defaultMinutesAfter: UInt = 35
    var minutesAfter: UInt = StopViewController.defaultMinutesAfter

    private var lastUpdated: Date?

    /// The number of seconds since this view controller was last updated.
    private var timeIntervalSinceLastUpdate: TimeInterval {
        if let lastUpdated = lastUpdated {
            return abs(lastUpdated.timeIntervalSinceNow)
        }
        else {
            return Double.greatestFiniteMagnitude
        }
    }

    /// Automatically reloads data every 'n' seconds.
    ///
    /// - Note: Calls  `timerFired()`  when its interval has elapsed.
    private var reloadTimer: Timer!

    /// The amount of time that must elapse before `timerFired()` will update data.
    private static let defaultTimerReloadInterval: TimeInterval = 30.0

    // MARK: - Data

    /// The data-loading operation for this controller.
    var operation: DecodableOperation<RESTAPIResponse<StopArrivals>>?

    /// The stop displayed by this controller.
    var stop: Stop? {
        didSet {
            if stop != oldValue, let stop = stop {
                stopUpdated(stop)
            }
        }
    }

    private func stopUpdated(_ stop: Stop) {
        if let region = application.currentRegion {
            application.userDataStore.addRecentStop(stop, region: region)
        }
        application.analytics?.reportStopViewed?(name: stop.name, id: stop.id, stopDistance: analyticsDistanceToStop)
    }

    /// Arrival/Departure data for this stop.
    var stopArrivals: StopArrivals? {
        didSet {
            if let stopArrivals = stopArrivals {
                stop = stopArrivals.stop
                dataDidReload()
                beginUserActivity()
            }
        }
    }

    // MARK: - Init/Deinit

    /// This initializer is the preferred way to create a `StopViewController`.
    /// Creates the view controller with a `Stop`, which allows the controller
    /// to immediately populate its header with information for the user.
    ///
    /// - Parameters:
    ///   - application: The application object
    ///   - stop: The stop the user is viewing
    public convenience init(application: Application, stop: Stop) {
        self.init(application: application, stopID: stop.id)
        self.stop = stop
        self.stopPreferences = application.stopPreferencesDataStore.preferences(stopID: stop.id, region: application.currentRegion!)

        stopUpdated(stop)
    }

    /// Creates the view controller with only a `stopID`, which requires
    /// information to be retrieved before a header can be rendered for the user.
    ///
    /// - Note: Although this initializer will display the same information to the
    ///         user as `init(application:stop:)`, that convenience initializer is
    ///         preferred as it can display information to the user more quickly.
    ///
    /// - Parameters:
    ///   - application: The application object
    ///   - stopID: The ID of the stop the user is viewing
    public init(application: Application, stopID: StopID) {
        self.application = application
        self.stopID = stopID
        self.stopPreferences = application.stopPreferencesDataStore.preferences(stopID: stopID, region: application.currentRegion!)

        super.init(nibName: nil, bundle: nil)

        registerDefaults()

        Timer.scheduledTimer(timeInterval: StopViewController.defaultTimerReloadInterval / 2.0, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)

        navigationItem.backBarButtonItem = UIBarButtonItem.backButton
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        reloadTimer.invalidate()
        enableIdleTimer()
        operation?.cancel()
    }

    // MARK: - UIViewController Overrides

    public override func viewDidLoad() {
        super.viewDidLoad()

        installSwipeOptionsNudge()

        view.backgroundColor = ThemeColors.shared.systemBackground

        listView.obaDataSource = self
        listView.contextMenuDelegate = self
        listView.collapsibleSectionsDelegate = self
        listView.formatters = application.formatters

        listView.register(listViewItem: ArrivalDepartureItem.self)
        listView.register(listViewItem: SegmentedControlItem.self)
        listView.register(listViewItem: StopArrivalWalkItem.self)
        listView.register(listViewItem: MessageButtonItem.self)
        listView.register(listViewItem: StopHeaderItem.self)
        listView.register(listViewItem: EmptyDataSetItem.self)

        view.addSubview(listView)
        listView.pinToSuperview(.edges)
        listView.addSubview(refreshControl)

        view.addSubview(fakeToolbar)

        let toolbarHeight: CGFloat = 44.0

        NSLayoutConstraint.activate([
            fakeToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fakeToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fakeToolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            fakeToolbar.heightAnchor.constraint(greaterThanOrEqualToConstant: toolbarHeight),
            fakeToolbar.stackWrapper.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        var inset = listView.contentInset
        inset.bottom = toolbarHeight + view.safeAreaInsets.bottom
        listView.contentInset = inset
        listView.scrollIndicatorInsets = inset

        if !stopViewShowsServiceAlerts {
            collapsedSections = [ListSections.serviceAlerts.sectionID]
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        disableIdleTimer()

        if stopArrivals != nil {
            beginUserActivity()
        }

        updateData()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        enableIdleTimer()
    }

    // MARK: - Idle Timer

    public var idleTimerFailsafe: Timer?

    // MARK: - Options Nudge

    /// This method will set up a UI affordance for showing the user how they can swipe on a stop arrival cell to see more options.
    ///
    /// If the user has already seen the nudge, as determined by user defaults, it will do nothing. Otherwise, an `AwesomeSpotlightView`
    /// will be displayed one second after the stop data finishes loading.
    private func installSwipeOptionsNudge() {
        guard application.userDefaults.bool(forKey: UserDefaultsKeys.shouldShowArrivalNudge) else {
            return
        }

//        collectionController.onReload = { [weak self] in
//            guard let self = self else { return }
//            for cell in self.collectionController.collectionView.sortedVisibleCells {
//                if let cell = cell as? StopArrivalCell,
//                   let arrDep = cell.arrivalDeparture,
//                   arrDep.temporalState != .past {
//                    self.showSwipeOptionsNudge(on: cell)
//                    self.collectionController.onReload = nil
//                    return
//                }
//            }
//        }
    }

    private func showSwipeOptionsNudge(on cell: StopArrivalCell) {
        guard
            let presentationWindow = view.window,
            let arrivalDeparture = cell.arrivalDeparture
        else { return }

        application.userDefaults.set(false, forKey: UserDefaultsKeys.shouldShowArrivalNudge)

        let frame = cell.convert(cell.bounds, to: presentationWindow)

        let locText: String

        if canCreateAlarm(for: arrivalDeparture) {
            locText = OBALoc("stop_controller.swipe_spotlight_text.with_alarm", value: "Swipe on a row to view more options, including adding alarms.", comment: "This is an instruction given to the user the first time they look at a stop view instructing them on how to access more options, including the ability to add alarms.")
        }
        else {
            locText = OBALoc("stop_controller.swipe_spotlight_text.without_alarm", value: "Swipe on a row to view more options.", comment: "This is an instruction given to the user the first time they look at a stop view instructing them on how to access more options, EXCLUDING the ability to add alarms.")
        }

        let text = NSAttributedString(string: locText, attributes: [
            NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .title1),
            NSAttributedString.Key.foregroundColor: UIColor.white,
            NSAttributedString.Key.shadow: NSShadow()
        ])

        let spotlight = AwesomeSpotlight(rect: frame, attributedText: text)
        let spotlightView = AwesomeSpotlightView(frame: presentationWindow.frame, spotlight: [spotlight])
        presentationWindow.addSubview(spotlightView)
        spotlightView.start {
            cell.showNudge()
        }
        self.spotlightView = spotlightView
    }

    private var spotlightView: AwesomeSpotlightView?

    // MARK: - User Defaults

    private struct UserDefaultsKeys {
        static let shouldShowArrivalNudge = "StopViewController.shouldShowArrivalNudge"
    }

    private func registerDefaults() {
        application.userDefaults.register(defaults: [
            UserDefaultsKeys.shouldShowArrivalNudge: true
        ])
    }

    // MARK: - Bottom Toolbar

    private lazy var refreshButton = FakeToolbar.buildToolbarButton(title: Strings.refresh, image: Icons.refresh, target: self, action: #selector(refresh))

    private lazy var bookmarkButton = FakeToolbar.buildToolbarButton(title: Strings.bookmark, image: Icons.addBookmark, target: self, action: #selector(addBookmark(sender:)))

    private lazy var filterButton = FakeToolbar.buildToolbarButton(title: Strings.filter, image: Icons.filter, target: self, action: #selector(filter))

    private lazy var fakeToolbar: FakeToolbar = {
        let toolbar = FakeToolbar(toolbarItems: [refreshButton, bookmarkButton, filterButton])
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        return toolbar
    }()

    // MARK: - NSUserActivity

    /// Creates and assigns an `NSUserActivity` object corresponding to this stop.
    private func beginUserActivity() {
        guard let stop = stop,
              let region = application.regionsService.currentRegion,
              let userActivityBuilder = application.userActivityBuilder
        else { return }

        self.userActivity = userActivityBuilder.userActivity(for: stop, region: region)
    }

    // MARK: - Data Loading

    /// Reloads data from the server and repopulates the UI once it finishes loading.
    func updateData() {
        operation?.cancel()

        guard let apiService = application.restAPIService else { return }

        title = Strings.updating
        navigationItem.rightBarButtonItem = UIActivityIndicatorView.asNavigationItem()

        let op = apiService.getArrivalsAndDeparturesForStop(id: stopID, minutesBefore: minutesBefore, minutesAfter: minutesAfter)
        op.complete { [weak self] result in
            guard let self = self else { return }

            let broken = self.bookmarkContext != nil && (op.statusCodeIsEffectively404 ?? false)

            switch (broken, result) {
            case (true, _):
                self.isBrokenBookmark = true
                self.listView.applyData()
            case (_, .failure(let error)):
                self.operationError = error
            case (false, .success(let response)):
                self.operationError = nil
                self.lastUpdated = Date()
                self.stopArrivals = response.entry
                self.refreshControl.endRefreshing()
                self.updateTitle()

                if response.entry.arrivalsAndDepartures.count == 0 {
                    self.extendLoadMoreWindow()
                }
            }

            self.navigationItem.rightBarButtonItem = nil
        }

        self.operation = op
    }

    /// Loads more departures for this `Stop` in cases where no `ArrivalDeparture` objects are being returned.
    /// This is useful for instances where you are looking at a `Stop` in the middle of the night and want to
    /// see when morning trips begin.
    private func extendLoadMoreWindow() {
        // Only load up to 12 hours worth of data.
        guard minutesAfter < 720 else { return }

        let minutes: UInt

        if self.minutesAfter < 60 {
            minutes = 60
        }
        else if self.minutesAfter < 240 {
            minutes = 60
        }
        else {
            minutes = 120
        }

        self.loadMore(minutes: minutes)
    }

    /// Callback used to reload the view controller every 'n' seconds.
    ///
    /// - Note: Driven by the private `reloadTimer` variable in this class.
    @objc private func timerFired() {
        if timeIntervalSinceLastUpdate > StopViewController.defaultTimerReloadInterval {
            updateData()
        }
    }

    /// Refreshes the view controller's title with the last time its data was reloaded.
    private func updateTitle() {
        if let lastUpdated = lastUpdated {
            let time = application.formatters.timeFormatter.string(from: lastUpdated)
            title = String(format: Strings.updatedAtFormat, time)
        }
    }

    // MARK: - Broken Bookmarks
    private var isBrokenBookmark: Bool = false

    // MARK: - OBAListView
    public func items(for listView: OBAListView) -> [OBAListViewSection] {
        if isBrokenBookmark { return [] }

        guard stopArrivals != nil else {
            if let error = self.operationError {
                let emptyDataItem = EmptyDataSetItem(id: "empty_data", error: error, image: nil, buttonConfig: operationRetryButton)
                return [stopHeaderSection, listViewSection(for: .emptyData, title: nil, items: [emptyDataItem])].compactMap { $0 }
            } else {
                return [stopHeaderSection].compactMap { $0 }
            }
            // TODO: show a loading message too
        }

        if inPreviewMode {
            return itemsForPreviewMode()
        } else {
            return itemsForRegularMode()
        }
    }

    private func itemsForRegularMode() -> [OBAListViewSection] {
        var sections: [OBAListViewSection?] = []

        let serviceAlerts = serviceAlertsSection
        let hiddenRoutes = hiddenRoutesToggle

        // When we are displaying service alerts, we should also show a header
        // for the section. However, don't show a header if a segmented control
        // for toggling hidden routes is visible.
        let showArrivalsHeader = serviceAlertsSection != nil && hiddenRoutes == nil

        sections.append(stopHeaderSection)
        sections.append(serviceAlerts)
        sections.append(hiddenRoutes)
        sections.append(contentsOf: stopArrivalsSection(showSectionHeaders: showArrivalsHeader))
        sections.append(loadMoreSection)
        sections.append(moreOptions)
        return sections.compactMap({ $0 })
    }

    private func itemsForPreviewMode() -> [OBAListViewSection] {
        var sections: [OBAListViewSection?] = []
        sections.append(stopHeaderSection)
        sections.append(contentsOf: stopArrivalsSection(showSectionHeaders: false))
        return sections.compactMap { $0 }
    }

    public func emptyData(for listView: OBAListView) -> OBAListView.EmptyData? {
        if isBrokenBookmark {
            let message = OBALoc("stop_controller.bad_bookmark_error_message", value: "This bookmark may not work anymore. Did your transit agency change something? Please delete and recreate the bookmark.", comment: "An error message displayed when a stop is shown by tapping on a bookmark—and the bookmark doesn't seem to point to a valid stop any longer. This problem will occur when a transit agency changes its stop IDs, perhaps as part of an annual transit system realignment.")

            let bookmarkBrokenImage = UIImage(systemName: "bookmark.slash.fill")?.withTintColor(.systemRed)    // iOS 14+ only.
            return .standard(.init(alignment: .center, title: "Broken Bookmark", body: message, image: bookmarkBrokenImage, buttonConfig: .none))
        }

        if let error = self.operationError {
            return .standard(.init(error: error))
        }

        return nil
    }

    // MARK: - Data/Stop Header
    private var stopHeaderSection: OBAListViewSection? {
        guard let stop = stop else { return nil }
        let item = StopHeaderItem(stop: stop, application: application)
        return listViewSection(for: .stopHeader, title: nil, items: [item])
    }

    // MARK: - Data/Stop Arrivals
    func stopArrivalsSection(showSectionHeaders: Bool) -> [OBAListViewSection] {
        guard let stopArrivals = self.stopArrivals else { return [] }
        var sections: [OBAListViewSection] = []

        if stopPreferences.sortType == .time {
            let arrDeps: [ArrivalDeparture]
            if isListFiltered {
                arrDeps = stopArrivals.arrivalsAndDepartures.filter(preferences: stopPreferences)
            } else {
                arrDeps = stopArrivals.arrivalsAndDepartures
            }
            sections = [sectionForGroup(groupRoute: nil, showSectionHeader: showSectionHeaders, arrDeps: arrDeps)]
        } else {
            let groups = stopArrivals.arrivalsAndDepartures.group(preferences: stopPreferences, filter: isListFiltered).localizedStandardCompare()
            // Regardless of the provided `showSectionHeader`, if stops are grouped by route, we will always show the section header.
            sections = groups.map { sectionForGroup(groupRoute: $0.route, showSectionHeader: true, arrDeps: $0.arrivalDepartures) }
        }

        return sections
    }

    private func arrivalDepartureItem(for arrivalDeparture: ArrivalDeparture) -> ArrivalDepartureItem {
        let alarmAvailable = canCreateAlarm(for: arrivalDeparture)
        return ArrivalDepartureItem(
            arrivalDeparture: arrivalDeparture,
            isAlarmAvailable: alarmAvailable,
            isDeepLinkingAvailable: application.features.deepLinking == .running,
            onSelectAction: didSelectArrivalDepartureItem,
            alarmAction: addAlarm,
            bookmarkAction: addBookmark,
            shareAction: shareTripStatus)
    }

    func sectionForGroup(groupRoute: Route?, showSectionHeader: Bool, arrDeps: [ArrivalDeparture]) -> OBAListViewSection {
        let sectionID: String
        let sectionName: String?
        if let groupRoute = groupRoute {
            sectionID = groupRoute.id
            sectionName = showSectionHeader ? (groupRoute.longName ?? groupRoute.shortName) : nil
        } else {
            sectionID = "all"
            sectionName = showSectionHeader ? OBALoc("stop_controller.arrival_departure_header", value: "Arrivals and Departures", comment: "A header for the arrivals and departures section of the stop controller.") : nil
        }

        let arrDepItems = arrDeps.map { arrivalDepartureItem(for: $0) }

        // Sometimes stopArrivals will respond with duplicate entries, so get rid of them.
        var items = Set(arrDepItems)
            .sorted(by: \.arrivalDepartureDate)
            .map { $0.typeErased }
        addWalkTimeRow(to: &items)

        return listViewSection(for: .arrivalDepartures(suffix: sectionID), title: sectionName, items: items)
    }

    /// Tracks arrival/departure times for `ArrivalDeparture`s.
    private var arrivalDepartureTimes = ArrivalDepartureTimes()

    // ^^^ note: I don't see any reason to destroy outmoded data. The size of an individual key/value pair
    //           is measured in bytes, and the lifecycle of this controller is quite short. If/when the
    //           lifecycle of a StopViewController is ever measured in days or weeks, then we should
    //           revisit this decision.

    func arrivalDeparture(forViewModel viewModel: ArrivalDepartureItem) -> ArrivalDeparture? {
        return stopArrivals?.arrivalsAndDepartures.filter({ $0.id == viewModel.identifier }).first
    }

    func didSelectArrivalDepartureItem(_ selectedItem: ArrivalDepartureItem) {
        guard let selectedArrivalDeparture = arrivalDeparture(forViewModel: selectedItem) else {
            return
        }
        self.application.viewRouter.navigateTo(arrivalDeparture: selectedArrivalDeparture, from: self)
    }

    private func stopArrivalContextMenu(_ viewModel: ArrivalDepartureItem) -> OBAListViewMenuActions {
        let preview: OBAListViewMenuActions.PreviewProvider = {
            return self.previewStopArrival(viewModel)
        }

        let performPreview: VoidBlock = {
            self.performPreviewStopArrival(viewModel)
        }

        let menuProvider: OBAListViewMenuActions.MenuProvider = { _ in
            var actions = [UIAction]()

            if viewModel.isAlarmAvailable {
                let alarm = UIAction(title: Strings.addAlarm, image: Icons.addAlarm) { _ in
                    self.addAlarm(viewModel: viewModel)
                }
                actions.append(alarm)
            }

            let addBookmark = UIAction(title: Strings.addBookmark, image: Icons.addBookmark) { _ in
                self.addBookmark(viewModel: viewModel)
            }
            actions.append(addBookmark)

            let shareTrip = UIAction(title: Strings.shareTrip, image: UIImage(systemName: "square.and.arrow.up")) { _ in
                self.shareTripStatus(viewModel: viewModel)
            }
            actions.append(shareTrip)

            // Create and return a UIMenu with all of the actions as children
            return UIMenu(title: viewModel.name, children: actions)
        }

        return OBAListViewMenuActions(previewProvider: preview, performPreviewAction: performPreview, contextMenuProvider: menuProvider)
    }

    private func previewStopArrival(_ viewModel: ArrivalDepartureItem) -> UIViewController? {
        guard let arrivalDeparture = self.arrivalDeparture(forViewModel: viewModel) else { return nil }
        let vc = TripViewController(application: self.application, arrivalDeparture: arrivalDeparture)
        self.previewingVC = (arrivalDeparture.id, vc)
        return vc
    }

    private func performPreviewStopArrival(_ viewModel: ArrivalDepartureItem) {
        if let previewingVC = self.previewingVC,
           previewingVC.identifier == viewModel.identifier,
           let tripVC = previewingVC.vc as? TripViewController {
            tripVC.exitPreviewMode()
            application.viewRouter.navigate(to: tripVC, from: self)
        } else {
            guard let arrivalDeparture = self.arrivalDeparture(forViewModel: viewModel) else { return }
            application.viewRouter.navigateTo(arrivalDeparture: arrivalDeparture, from: self)
        }
    }

    /// Used to determine if the highlight change label in the `ArrivalDeparture`'s collection cell should 'flash' when next rendered.
    ///
    /// This is used to indicate whether the departure time for the `ArrivalDeparture` object has changed.
    ///
    /// - Parameter arrivalDeparture: The ArrivalDeparture object
    /// - Returns: Whether or not to highlight the ArrivalDeparture in its cell.
    private func shouldHighlight(arrivalDeparture: ArrivalDeparture) -> Bool {
        var highlight = false
        if let lastMinutes = arrivalDepartureTimes[arrivalDeparture.tripID] {
            highlight = lastMinutes != arrivalDeparture.arrivalDepartureMinutes
        }

        arrivalDepartureTimes[arrivalDeparture.tripID] = arrivalDeparture.arrivalDepartureMinutes

        return highlight
    }

    private func findInsertionIndexForWalkTime(_ walkTimeInterval: TimeInterval, items: [AnyOBAListViewItem]) -> Int? {
        for (idx, elt) in items.enumerated() {
            guard let arrDep = elt.as(ArrivalDepartureItem.self) else { continue }
            let interval = arrDep.scheduledDate.timeIntervalSinceNow
            if interval >= walkTimeInterval { return idx }
        }
        return nil
    }

    private func addWalkTimeRow(to items: inout [AnyOBAListViewItem]) {
        guard items.count > 0,
              let currentLocation = application.locationService.currentLocation,
              let stopLocation = stop?.location,
              let walkingTime = WalkingDirections.travelTime(from: currentLocation, to: stopLocation)
        else { return }

        if let insertionIndex = findInsertionIndexForWalkTime(walkingTime, items: items) {
            let distance = currentLocation.distance(from: stopLocation)
            let walkItem = StopArrivalWalkItem(id: "walk_item", distance: distance, timeToWalk: walkingTime)
            items.insert(walkItem.typeErased, at: insertionIndex)
        }
    }

    // MARK: - Data/Service Alerts

    private var serviceAlertsSection: OBAListViewSection? {
        guard let alerts = stopArrivals?.serviceAlerts, alerts.count > 0 else { return nil }
        let items = alerts.map { TransitAlertDataListViewModel($0, forLocale: .current, onSelectAction: didSelectAlert) }

        let sectionTitle: String
        if alerts.count == 1 {
            sectionTitle = Strings.serviceAlert
        } else {
            // Indicate how many service alerts there are.
            sectionTitle = "\(Strings.serviceAlerts) (\(alerts.count))"
        }

        return listViewSection(for: .serviceAlerts, title: sectionTitle, items: items)
    }

    // MARK: - Data/Hidden Routes Toggle

    private var hiddenRoutesToggle: OBAListViewSection? {
        guard stopPreferences.hasHiddenRoutes else { return nil }

        // If we have hidden routes, then show the hide/show filter toggle.
        let segments = [
            OBALoc("stop_controller.filter_toggle.all_departures", value: "All Departures", comment: "Segmented control item: show all departures"),
            OBALoc("stop_controller.filter_toggle.filtered_departures", value: "Filtered Departures", comment: "Segmented control item: show filtered departures")
        ]

        let selectedIndex = isListFiltered ? 1 : 0
        let toggleItem = SegmentedControlItem(id: "hidden_routes_toggle", segments: segments, initialSelectedIndex: selectedIndex) { [weak self] _ in
            self?.isListFiltered.toggle()
        }

        return listViewSection(for: .hiddenRoutesToggle, title: nil, items: [toggleItem])
    }

    // MARK: - Data/Load More

    private var loadMoreSection: OBAListViewSection {
        let beforeTime = Date().addingTimeInterval(Double(minutesBefore) * -60.0)
        let afterTime = Date().addingTimeInterval(Double(minutesAfter) * 60.0)
        let footerText = application.formatters.formattedDateRange(from: beforeTime, to: afterTime)

        let item = MessageButtonItem(asLoadMoreButtonWithID: "load_more_item", error: operationError, footerText: footerText, showActivityIndicatorOnSelect: true) { [weak self] _ in
            self?.loadMoreDepartures()
        }

        return listViewSection(for: .loadMoreButton, title: nil, items: [item])
    }

    // MARK: - Data/More Options

    private var moreOptions: OBAListViewSection {
        var items: [AnyOBAListViewItem] = []

        if let stop = stop {
            let nearbyStops = OBAListRowView.DefaultViewModel(title: OBALoc("stops_controller.nearby_stops", value: "Nearby Stops", comment: "Title of the row that will show stops that are near this one."), accessoryType: .disclosureIndicator) { [weak self] _ in
                guard let self = self else { return }
                let nearbyController = NearbyStopsViewController(coordinate: stop.coordinate, application: self.application)
                self.application.viewRouter.navigate(to: nearbyController, from: self)
            }
            items.append(nearbyStops.typeErased)

            let appleMaps = OBAListRowView.DefaultViewModel(title: OBALoc("stops_controller.walking_directions_apple", value: "Walking Directions (Apple Maps)", comment: "Button that launches Apple's maps.app with walking directions to this stop"), accessoryType: .disclosureIndicator) { [weak self] _ in
                guard
                    let self = self,
                    let url = AppInterop.appleMapsWalkingDirectionsURL(coordinate: stop.coordinate)
                    else { return }

                self.application.open(url, options: [:], completionHandler: nil)
            }
            items.append(appleMaps.typeErased)

            #if !targetEnvironment(simulator)
            let googleMaps = OBAListRowView.DefaultViewModel(title: OBALoc("stops_controller.walking_directions_google", value: "Walking Directions (Google Maps)", comment: "Button that launches Google Maps with walking directions to this stop"), accessoryType: .disclosureIndicator) { [weak self] _ in
                guard
                    let self = self,
                    let url = AppInterop.googleMapsWalkingDirectionsURL(coordinate: stop.coordinate),
                    self.application.canOpenURL(url)
                else { return }

                self.application.open(url, options: [:], completionHandler: nil)
            }
            items.append(googleMaps.typeErased)
            #endif
        }

        // Report Problem
        let reportProblem = OBAListRowView.DefaultViewModel(title: OBALoc("stops_controller.report_problem", value: "Report a Problem", comment: "Button that launches the 'Report Problem' UI."), accessoryType: .disclosureIndicator) { [weak self] _ in
            self?.showReportProblem()
        }
        items.append(reportProblem.typeErased)

        // All Service Alerts
        if let alerts = stopArrivals?.serviceAlerts, alerts.count > 0 {
            let row = OBAListRowView.DefaultViewModel(title: Strings.serviceAlerts, accessoryType: .disclosureIndicator) { _ in
                let controller = ServiceAlertListController(application: self.application, serviceAlerts: alerts)
                self.application.viewRouter.navigate(to: controller, from: self)
            }
            items.append(row.typeErased)
        }

        return listViewSection(for: .moreOptions, title: OBALoc("stops_controller.more_options", value: "More Options", comment: "More Options section header on the Stops controller"), items: items)
    }

    /// Call this method after data has been reloaded in this controller
    private func dataDidReload() {
        listView.applyData(animated: false)
    }

    var operationError: Error? {
        didSet {
            if operationError?.localizedDescription != oldValue?.localizedDescription {
                self.listView.applyData(animated: true)
            }
        }
    }

    lazy var operationRetryButton = ActivityIndicatedButton.Configuration(text: "Retry", largeContentImage: Icons.refresh, showsActivityIndicatorOnTap: true) { [weak self] in
        self?.refresh()
    }

//    public func emptyView(for listAdapter: ListAdapter) -> UIView? {
//        guard let error = operationError else { return nil }
//
//        let emptyView = EmptyDataSetView(alignment: .center)
//        emptyView.configure(with: error, buttonConfig: operationRetryButton)
//
//        return emptyView
//    }

    // MARK: - Collection Controller
    private lazy var listView = OBAListView()
    public var collapsedSections: Set<OBAListViewSection.ID> = [] {
        didSet {
            didCollapseSection()
        }
    }
    public var selectionFeedbackGenerator: UISelectionFeedbackGenerator?

    private lazy var refreshControl: UIRefreshControl = {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        return refreshControl
    }()

    public func canCollapseSection(_ listView: OBAListView, section: OBAListViewSection) -> Bool {
        return section.id == ListSections.serviceAlerts.sectionID
    }

    func didCollapseSection() {
        self.stopViewShowsServiceAlerts = !collapsedSections.contains(ListSections.serviceAlerts.sectionID)
    }

    // Helper.
    func listViewSection<Item: OBAListViewItem>(for section: ListSections, title: String?, items: [Item]) -> OBAListViewSection {
        return OBAListViewSection(id: section.sectionID, title: title, contents: items)
    }

    var previewingVC: (identifier: String, vc: UIViewController)?
    public func contextMenu(_ listView: OBAListView, for item: AnyOBAListViewItem) -> OBAListViewMenuActions? {
        if let arrDepItem = item.as(ArrivalDepartureItem.self) {
            return stopArrivalContextMenu(arrDepItem)
        }
        return nil
    }

    // MARK: - ServiceAlertsSectionController methods
    /// Whether the map view shows the direction the user is currently facing in.
    ///
    /// Defaults to `true`.
    public var stopViewShowsServiceAlerts: Bool {
        get { application.userDefaults.bool(forKey: stopViewShowsServiceAlertsKey) }
        set { application.userDefaults.set(newValue, forKey: stopViewShowsServiceAlertsKey) }
    }
    private let stopViewShowsServiceAlertsKey = "stopViewShowsServiceAlerts"

    func didSelectAlert(_ viewModel: TransitAlertDataListViewModel) {
        application.viewRouter.navigateTo(alert: viewModel.transitAlert, from: self)
    }

    func serviceAlertsSectionController(_ controller: ServiceAlertsSectionController, didSelectAlert alert: ServiceAlert) {
        let serviceAlertController = ServiceAlertViewController(serviceAlert: alert, application: self.application)
        let nc = UINavigationController(rootViewController: serviceAlertController)
        self.present(nc, animated: true)
    }

    // MARK: - Stop Arrival Actions

    public func showMoreOptions(arrivalDeparture: ArrivalDeparture, sourceView: UIView?, sourceFrame: CGRect?) {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        actionSheet.addAction(title: Strings.addBookmark) { [weak self] _ in
            guard let self = self else { return }
            self.addBookmark(arrivalDeparture: arrivalDeparture)
        }

        if application.features.deepLinking == .running {
            actionSheet.addAction(title: Strings.shareTrip) { [weak self] _ in
                guard let self = self else { return }
                self.shareTripStatus(arrivalDeparture: arrivalDeparture)
            }
        }

        actionSheet.addAction(UIAlertAction.cancelAction)

        application.viewRouter.present(
            actionSheet,
            from: self,
            isPopover: traitCollection.userInterfaceIdiom == .pad,
            popoverSourceView: sourceView,
            popoverSourceFrame: sourceFrame
        )
    }

    // MARK: - Alarms

    private func canCreateAlarm(for arrivalDeparture: ArrivalDeparture) -> Bool {
        guard
            application.features.obaco == .running,
            application.features.push == .running
        else {
            return false
        }

        return arrivalDeparture.temporalState == .future
    }

    private var alarmBuilder: AlarmBuilder?

    func addAlarm(viewModel: ArrivalDepartureItem) {
        guard let arrivalDeparture = arrivalDeparture(forViewModel: viewModel) else { return }
        addAlarm(arrivalDeparture: arrivalDeparture)
    }

    func addAlarm(arrivalDeparture: ArrivalDeparture) {
        alarmBuilder = AlarmBuilder(arrivalDeparture: arrivalDeparture, application: application, delegate: self)
        alarmBuilder?.showBulletin(above: self)
    }

    func alarmBuilderStartedRequest(_ alarmBuilder: AlarmBuilder) {
        ProgressHUD.show()
    }

    func alarmBuilder(_ alarmBuilder: AlarmBuilder, alarmCreated alarm: Alarm) {
        application.userDataStore.add(alarm: alarm)

        let message = OBALoc("stop_controller.alarm_created_message", value: "Alarm created", comment: "A message that appears when a user's alarm is created.")
        ProgressHUD.showSuccessAndDismiss(message: message)
    }

    func alarmBuilder(_ alarmBuilder: AlarmBuilder, error: Error) {
        ProgressHUD.dismiss()
        AlertPresenter.show(error: error, presentingController: self)
    }

    // MARK: - Bookmarks
    private func addBookmark(viewModel: ArrivalDepartureItem) {
        guard let arrivalDeparture = arrivalDeparture(forViewModel: viewModel) else { return }
        addBookmark(arrivalDeparture: arrivalDeparture)
    }

    private func addBookmark(arrivalDeparture: ArrivalDeparture) {
        let bookmarkController = EditBookmarkViewController(application: application, arrivalDeparture: arrivalDeparture, bookmark: nil, delegate: self)
        let navigation = UINavigationController(rootViewController: bookmarkController)

        application.viewRouter.present(navigation, from: self)
    }

    // MARK: - Bookmark Editor

    func bookmarkEditorCancelled(_ viewController: UIViewController) {
        viewController.dismiss(animated: true, completion: nil)
    }

    func bookmarkEditor(_ viewController: UIViewController, editedBookmark bookmark: Bookmark, isNewBookmark: Bool) {
        viewController.dismiss(animated: true) {
            let msg = isNewBookmark ? OBALoc("stops_controller.created_new_bookmark", value: "Added Bookmark", comment: "Message displayed when a new bookmark is created.") : OBALoc("stops_controller.updated_bookmark", value: "Updated Bookmark", comment: "Message displayed an existing bookmark is updated.")
            ProgressHUD.showSuccessAndDismiss(message: msg, dismissAfter: 1.0)
        }
    }

    // MARK: - Share Trip Status
    func shareTripStatus(viewModel: ArrivalDepartureItem) {
        guard let arrivalDeparture = arrivalDeparture(forViewModel: viewModel) else { return }
        shareTripStatus(arrivalDeparture: arrivalDeparture)
    }

    func shareTripStatus(arrivalDeparture: ArrivalDeparture) {
        guard
            let region = application.currentRegion,
            let appLinksRouter = application.appLinksRouter
        else {
            return
        }

        let url = appLinksRouter.encode(arrivalDeparture: arrivalDeparture, region: region)

        let activityController = UIActivityViewController(activityItems: [self, url], applicationActivities: nil)
        application.viewRouter.present(activityController, from: self, isModal: true)
    }

    // MARK: - Actions

    /// Reloads data.
    @objc private func refresh() {
        // Debounce this action in order to prevent the user
        // from spamming the server with a ton of requests.
        DispatchQueue.main.debounce(interval: 1.0) { [weak self] in
            guard let self = self else { return }
            self.updateData()
        }
    }

    /// Initiates the 'Add Bookmark' workflow.
    @objc private func addBookmark(sender: Any?) {
        guard let stop = stop else { return }

        let bookmarkController = AddBookmarkViewController(application: application, stop: stop, delegate: self)

        let navigation = application.viewRouter.buildNavigation(controller: bookmarkController)
        application.viewRouter.present(navigation, from: self, isModal: true)
    }

    /// Initiates the Route Filter workflow.
    @objc private func filter() {
        guard let stop = stop else { return }

        let stopPreferencesController = StopPreferencesViewController(application: application, stop: stop, delegate: self)
        let navigation = UINavigationController(rootViewController: stopPreferencesController)
        present(navigation, animated: true, completion: nil)
    }

    /// Extends the `ArrivalDeparture` time window visualized by this view controller and reloads data.
    private func loadMore(minutes: UInt) {
        minutesAfter += minutes
        updateData()
    }

    @objc private func loadMoreDepartures() {
        loadMore(minutes: 30)
    }

    /// Shows the Report Problem UI.
    @objc private func showReportProblem() {
        guard let stop = stop else { return }

        let reportProblemController = ReportProblemViewController(application: application, stop: stop)
        let navigation = application.viewRouter.buildNavigation(controller: reportProblemController)
        application.viewRouter.present(navigation, from: self, isModal: true)
    }

    // MARK: - Modal Delegate

    public func dismissModalController(_ controller: UIViewController) {
        // For other view controllers
        controller.dismiss(animated: true, completion: nil)
    }

    // MARK: - Stop Preferences

    private var stopPreferences: StopPreferences {
        didSet {
            dataDidReload()
        }
    }

    func stopPreferences(_ controller: StopPreferencesViewController, updated stopPreferences: StopPreferences) {
        self.stopPreferences = stopPreferences
    }

    private var isListFiltered: Bool = true {
        didSet {
            dataDidReload()
        }
    }

    // MARK: - Previewable

    private var inPreviewMode = false

    func enterPreviewMode() {
        fakeToolbar.isHidden = true
        inPreviewMode = true
    }

    func exitPreviewMode() {
        fakeToolbar.isHidden = false
        inPreviewMode = false
    }

    // MARK: - Analytics

    private var analyticsDistanceToStop: String {
        guard
            let userLocation = application.locationService.currentLocation,
            let stopLocation = stop?.location
        else {
            return "User Distance: 03200-INFINITY"
        }

        let distance = userLocation.distance(from: stopLocation)

        if distance < 50 {
            return "User Distance: 00000-00050m"
        }
        else if distance < 100 {
            return "User Distance: 00050-00100m"
        }
        else if distance < 200 {
            return "User Distance: 00100-00200m"
        }
        else if distance < 400 {
            return "User Distance: 00200-00400m"
        }
        else if distance < 800 {
            return "User Distance: 00400-00800m"
        }
        else if distance < 1600 {
            return "User Distance: 00800-01600m"
        }
        else if distance < 3200 {
            return "User Distance: 01600-03200m"
        }
        else {
            return "User Distance: 03200-INFINITY"
        }
    }
}
