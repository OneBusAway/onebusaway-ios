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
import SwiftUI
#if canImport(Stripe)
import StripePaymentSheet
#endif

// swiftlint:disable file_length

/// This is the core view controller for displaying information about a transit stop.
///
/// Specifically, `StopViewController` provides you with information about upcoming
/// arrivals and departures at this stop, along with the ability to create push
/// notification 'alarms' and bookmarks, view information about the location of a
/// particular vehicle, and report problems with a trip.
public class StopViewController: UIViewController,
    AlarmBuilderDelegate,
    AgencyAlertListViewConverters,
    AppContext,
    BookmarkEditorDelegate,
    Idleable,
    OBAListViewDataSource,
    OBAListViewDelegate,
    OBAListViewContextMenuDelegate,
    OBAListViewCollapsibleSectionsDelegate,
    ModalDelegate,
    Previewable,
    StopPreferencesViewDelegate {

    /// The available sections in this view controller.
    enum ListSections {
        case stopHeader
        case donations
        case emptyData
        case serviceAlerts
        case arrivalDepartures(suffix: String)
        case loadMoreButton
        case dataAttribution

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

        reloadTimer = Timer.scheduledTimer(withTimeInterval: StopViewController.defaultTimerReloadInterval / 2.0, repeats: true) { [weak self] _ in
            self?.timerFired()
        }

        navigationItem.backBarButtonItem = UIBarButtonItem.backButton
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        reloadTimer.invalidate()
        enableIdleTimer()
    }

    // MARK: - UIViewController Overrides
    public override func loadView() {
        super.loadView()
        self.view = listView
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground

        listView.obaDelegate = self
        listView.obaDataSource = self
        listView.contextMenuDelegate = self
        listView.collapsibleSectionsDelegate = self
        listView.formatters = application.formatters

        listView.register(listViewItem: ArrivalDepartureItem.self)
        listView.register(listViewItem: DonationListItem.self)
        listView.register(listViewItem: EmptyDataSetItem.self)
        listView.register(listViewItem: MessageButtonItem.self)
        listView.register(listViewItem: StopArrivalWalkItem.self)
        listView.register(listViewItem: StopHeaderItem.self)

        listView.pinToSuperview(.edges)
        listView.addSubview(refreshControl)

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

        Task {
            await updateData()
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        enableIdleTimer()
    }

    // MARK: - Idle Timer

    public var idleTimerFailsafe: Timer?

    // MARK: - Options Nudge
    private func showSwipeOptionsNudge(on cell: StopArrivalCell) {
        guard let presentationWindow = view.window else { return }

        application.userDefaults.set(false, forKey: UserDefaultsKeys.shouldShowArrivalNudge)

        let frame = cell.convert(cell.bounds, to: presentationWindow)

        let locText: String
        if cell.canCreateAlarmForArrivalDeparture {
            locText = OBALoc("stop_controller.swipe_spotlight_text.with_alarm", value: "Swipe on a row to view more options, including adding alarms.", comment: "This is an instruction given to the user the first time they look at a stop view instructing them on how to access more options, including the ability to add alarms.")
        } else {
            locText = OBALoc("stop_controller.swipe_spotlight_text.without_alarm", value: "Swipe on a row to view more options.", comment: "This is an instruction given to the user the first time they look at a stop view instructing them on how to access more options, EXCLUDING the ability to add alarms.")
        }

        let text = NSAttributedString(string: locText, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .title1),
            .foregroundColor: UIColor.white,
            .shadow: NSShadow()
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

    // MARK: - Dropdown Menus
    fileprivate func configureTabBarButtons() {
        let filterButtonImage: UIImage?
        let filterButtonTitle: String

        // On iOS 15+ (SFSymbols 3.0), the symbol name is `line.3.horizontal.decrease.circle`.
        // On iOS 13+ (SFSymbols 1.0), the symbol name is `line.horizontal.3.decrease.circle`.
        if stopPreferences.hasHiddenRoutes && isListFiltered {
            filterButtonTitle = "FILTER (ON)"
            if #available(iOS 15, *) {
                filterButtonImage = UIImage(systemName: "line.3.horizontal.decrease.circle.fill")
            } else {
                filterButtonImage = UIImage(systemName: "line.horizontal.3.decrease.circle.fill")
            }
        } else {
            filterButtonTitle = "FILTER (OFF)"
            if #available(iOS 15, *) {
                filterButtonImage = UIImage(systemName: "line.3.horizontal.decrease.circle")
            } else {
                filterButtonImage = UIImage(systemName: "line.horizontal.3.decrease.circle")
            }
        }

        let filterMenuButton = UIBarButtonItem(title: filterButtonTitle, image: filterButtonImage, menu: filterMenu())
        let moreMenuButton = UIBarButtonItem(title: "MORE", image: UIImage(systemName: "ellipsis.circle"), menu: pulldownMenu())
        navigationItem.rightBarButtonItems = [moreMenuButton, filterMenuButton]
    }

    fileprivate func pulldownMenu() -> UIMenu {
        return UIMenu(children: [fileMenu(), locationMenu(), sortMenu(), helpMenu()])
    }

    func filterMenu() -> UIMenu {
        let allRoutesTitle = OBALoc("stops_controller.filter.all_routes", value: "All Routes", comment: "A menu item on a Stop page that toggles the visible list of transit vehicles from a filtered list to all of the list items. e.g. a stop serves routes 1, 2, and 3. The user has filtered the stop to only show route 3. Chooosing this item will show 1, 2, and 3 again.")
        let filteredRoutesTitle = OBALoc("stops_controller.filter.filtered_routes", value: "Filtered Routes", comment: "A menu item on a Stop page that toggles the visible list of transit vehicles from a list of all items to a filtered list. e.g. a stop serves routes 1, 2, and 3. The user wants to only view route 3. Choosing this item would show that subset of routes.")

        let showAll = UIAction(title: allRoutesTitle) { [unowned self] _ in
            if self.isListFiltered {
                // Only change value if it's different to avoid unnecessary data loading.
                self.isListFiltered = false
            }
        }

        let showFiltered = UIAction(title: filteredRoutesTitle) { [unowned self] _ in
            self.isListFiltered = true
            self.filter()
        }

        if isListFiltered && stopPreferences.hasHiddenRoutes {
            showFiltered.image = UIImage(systemName: "checkmark")
        } else {
            showAll.image = UIImage(systemName: "checkmark")
        }

        return UIMenu(children: [showAll, showFiltered])
    }

    fileprivate func fileMenu() -> UIMenu {
        let bookmarkAction = UIAction(title: Strings.addBookmark, image: UIImage(systemName: "bookmark")) { [unowned self] action in
            self.addBookmark(sender: action)
        }

        let alertsAction = UIAction(title: Strings.serviceAlerts, image: UIImage(systemName: "exclamationmark.circle")) { [unowned self] _ in
            let controller = ServiceAlertListController(application: self.application, serviceAlerts: self.stopArrivals?.serviceAlerts ?? [])
            self.application.viewRouter.navigate(to: controller, from: self)
        }

        // Disable the alerts action if there are no service alerts.
        if (stopArrivals?.serviceAlerts ?? []).isEmpty {
            alertsAction.attributes = .disabled
        }

        return UIMenu(title: "File", options: .displayInline, children: [bookmarkAction, alertsAction])
    }

    fileprivate func locationMenu() -> UIMenu {
        let nearbyAction = UIAction(title: OBALoc("stops_controller.nearby_stops", value: "Nearby Stops", comment: "Title of the row that will show stops that are near this one."), image: UIImage(systemName: "location")) { [unowned self] _ in
            let nearbyController = NearbyStopsViewController(coordinate: self.stop!.coordinate, application: self.application)
            self.application.viewRouter.navigate(to: nearbyController, from: self)
        }

        var walkingDirectionActions: [UIMenuElement] = []

        if let stop = self.stop {
            if let appleMapsURL = AppInterop.appleMapsWalkingDirectionsURL(coordinate: stop.coordinate) {
                let appleMaps = UIAction(title: OBALoc("stops_controller.walking_directions_apple", value: "Walking Directions (Apple Maps)", comment: "Button that launches Apple's maps.app with walking directions to this stop")) { [unowned self] _ in
                    self.application.open(appleMapsURL, options: [:], completionHandler: nil)
                }
                walkingDirectionActions.append(appleMaps)
            }

            #if !targetEnvironment(simulator)
            // Display Google Maps app link, only if Google Maps is installed.
            if let googleMapsURL = AppInterop.googleMapsWalkingDirectionsURL(coordinate: stop.coordinate),
               self.application.canOpenURL(googleMapsURL) {
                let googleMaps = UIAction(title: OBALoc("stops_controller.walking_directions_google", value: "Walking Directions (Google Maps)", comment: "Button that launches Google Maps with walking directions to this stop")) { [unowned self] _ in
                    self.application.open(googleMapsURL, options: [:], completionHandler: nil)
                }
                walkingDirectionActions.append(googleMaps)
            }
            #endif
        }

        let walkingDirectionsElement: UIMenuElement
        let walkingDirectionsTitle = OBALoc("stops_controller.walking_directions", value: "Walking Directions", comment: "Button that launches a maps app with walking directions to this stop")
        let walkingDirectionsImage = UIImage(systemName: "figure.walk")

        // Show a disabled walking directions button if there are no Walking Directions apps available.
        if walkingDirectionActions.isEmpty {
            walkingDirectionsElement = UIAction(title: walkingDirectionsTitle, image: walkingDirectionsImage, attributes: .disabled) { _ in /* noop */ }
        } else {
            walkingDirectionsElement = UIMenu(title: walkingDirectionsTitle, image: walkingDirectionsImage, children: walkingDirectionActions)
        }

        return UIMenu(title: "Location", options: .displayInline, children: [nearbyAction, walkingDirectionsElement])
    }

    fileprivate func sortMenu() -> UIMenu {
        var preferences = application.stopPreferencesDataStore.preferences(stopID: self.stopID, region: self.application.currentRegion!)

        let sortByTimeTitle = OBALoc("stop_preferences_controller.sorting_section.sort_by_time", value: "Sort by time", comment: "Sort by time option")
        let sortByRouteTitle = OBALoc("stop_preferences_controller.sorting_section.sort_by_route", value: "Sort by route", comment: "Sort by route option")

        let sortByTime = UIAction(title: sortByTimeTitle) { [unowned self] _ in
            preferences.sortType = .time
            self.application.stopPreferencesDataStore.set(stopPreferences: preferences, stop: self.stop!, region: self.application.currentRegion!)
            self.stopPreferences = preferences
        }

        let sortByRoute = UIAction(title: sortByRouteTitle) { [unowned self] _ in
            preferences.sortType = .route
            self.application.stopPreferencesDataStore.set(stopPreferences: preferences, stop: self.stop!, region: self.application.currentRegion!)
            self.stopPreferences = preferences
        }

        // Show a checkmark by the current sort type.
        switch preferences.sortType {
        case .time:  sortByTime.image =  UIImage(systemName: "checkmark")
        case .route: sortByRoute.image = UIImage(systemName: "checkmark")
        }

        var sortMenu: UIMenu
        let sortMenuTitle = OBALoc("stop_preferences_controller.sorting_section.header_title", value: "Sort By", comment: "Title of the Sorting section")
        let sortMenuImage = UIImage(systemName: "arrow.up.arrow.down")
        if #available(iOS 15, *) {
            // Submenus in iOS 15 looks better.
            sortMenu = UIMenu(title: sortMenuTitle, image: sortMenuImage, children: [sortByTime, sortByRoute])
        } else {
            sortMenu = UIMenu(title: sortMenuTitle, image: sortMenuImage, options: .displayInline, children: [sortByTime, sortByRoute])
        }

        return sortMenu
    }

    fileprivate func helpMenu() -> UIMenu {
        let reportButton = UIAction(title: OBALoc("stops_controller.report_problem", value: "Report a Problem", comment: "Button that launches the 'Report Problem' UI."), image: UIImage(systemName: "exclamationmark.bubble")) { [unowned self] _ in
            self.showReportProblem()
        }

        return UIMenu(title: "Help", options: .displayInline, children: [reportButton])
    }

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

    private lazy var dataLoadFeedbackGenerator = DataLoadFeedbackGenerator(application: application)

    /// Used to control behavior on the first load of data from the server in this controller.
    private var firstLoad = true

    /// Reloads data from the server and repopulates the UI once it finishes loading.
    func updateData() async {
        guard let apiService = application.apiService else { return }

        title = Strings.updating

        do {
            let stopArrivals = try await apiService.getArrivalsAndDeparturesForStop(id: stopID, minutesBefore: minutesBefore, minutesAfter: minutesAfter).entry

            await MainActor.run {
                self.operationError = nil
                self.lastUpdated = Date()
                self.stopArrivals = stopArrivals
                self.refreshControl.endRefreshing()
                self.updateTitle()
                if stopArrivals.arrivalsAndDepartures.count == 0 {
                    self.extendLoadMoreWindow()
                }

                if self.firstLoad {
                    self.firstLoad = false
                } else {
                    self.dataLoadFeedbackGenerator.dataLoad(.success)
                }
            }
        } catch APIError.requestNotFound {
            self.isBrokenBookmark = self.bookmarkContext != nil
            self.dataLoadFeedbackGenerator.dataLoad(.failed)
        } catch {
            self.operationError = error
            self.dataLoadFeedbackGenerator.dataLoad(.failed)
        }

        self.listView.applyData()
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
        updateTitle()

        if timeIntervalSinceLastUpdate > StopViewController.defaultTimerReloadInterval {
            Task {
                await updateData()
            }
        }
    }

    /// Refreshes the view controller's title with the last time its data was reloaded.
    private func updateTitle() {
        guard let lastUpdated = lastUpdated else {
            return
        }

        title = String(format: Strings.updatedAtFormat, application.formatters.timeAgoInWords(date: lastUpdated))
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

        sections.append(stopHeaderSection)

        if let donationsSection {
            sections.append(donationsSection)
        }

        sections.append(serviceAlertsSection)
        sections.append(contentsOf: stopArrivalsSection)

        if self.stopPreferences.sortType == .route {
            sections.append(listViewSection(for: .loadMoreButton, title: nil, items: loadMoreItems))
        }

        sections.append(dataAttributionSection)
        return sections.compactMap({ $0 })
    }

    private func itemsForPreviewMode() -> [OBAListViewSection] {
        var sections: [OBAListViewSection?] = []
        sections.append(stopHeaderSection)
        sections.append(contentsOf: stopArrivalsSection)
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

    public func didApplyData(_ listView: OBAListView) {
        // Due to an OBAListView bug, applying data causes the entire list view
        // to reload, scrolling the user back to the top of the page.
        // If the user initiated the applyData call from the "LOAD MORE" button,
        // manually scroll the user back to the bottom of the arrDeps section
        // to maintain UX continuity.
        // Related 1: #389 -- OBAListView still has identity problems, causing crashes
        // Related 2: https://github.com/OneBusAway/OBAKit/issues/389#issuecomment-867014676

        if self.shouldScrollToBottomOfArrivalsDeparuresOnDataLoad {
            listView.scrollTo(section: dataAttributionSection, at: .bottom, animated: false)
            shouldScrollToBottomOfArrivalsDeparuresOnDataLoad = false
        }
        // This method will set up a UI affordance for showing the user how
        // they can swipe on a stop arrival cell to see more options.
        //
        // If the user has already seen the nudge, as determined by user
        // defaults, it will do nothing. Otherwise, an `AwesomeSpotlightView`
        // will be displayed one second after the stop data finishes loading.

        // Disabled code: see #401 -- List view show nudge action doesn't work
//        guard application.userDefaults.bool(forKey: UserDefaultsKeys.shouldShowArrivalNudge) else {
//            return
//        }
//
//        for cell in listView.sortedVisibleCells {
//            if let cell = cell as? StopArrivalCell,
//               !cell.isShowingPastArrivalDeparture {
//                self.showSwipeOptionsNudge(on: cell)
//                return
//            }
//        }
    }

    // MARK: - Data/Stop Header

    private var stopHeaderSection: OBAListViewSection? {
        guard let stop = stop else { return nil }
        let item = StopHeaderItem(stop: stop, application: application)
        return listViewSection(for: .stopHeader, title: nil, items: [item])
    }

    // MARK: - Data/Donations

    private var donationsSection: OBAListViewSection? {
        guard application.donationsManager.shouldRequestDonations else { return nil }
        let item = DonationListItem { [weak self] _ in
            self?.showDonationUI()
        } onLearnMoreAction: { [weak self] _ in
            self?.showDonationUI()
        } onCloseAction: { [weak self] _ in
            self?.showDonationDismissUI()
        }

        return listViewSection(for: .donations, title: nil, items: [item])
    }

    private func showDonationUI() {
#if canImport(Stripe)
        guard
            application.donationsManager.donationsEnabled,
            let donationModel = application.donationsManager.buildObservableDonationModel()
        else {
            return
        }

        let learnMoreView = DonationLearnMoreView { [weak self] donated in
            guard donated else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self?.present(DonationsManager.buildDonationThankYouAlert(), animated: true)
                self?.application.donationsManager.dismissDonationsRequests()
                self?.refresh()
            }
        }
            .environmentObject(donationModel)
            .environmentObject(AnalyticsModel(application.analytics))

        present(UIHostingController(rootView: learnMoreView), animated: true)
#endif
    }

    private func showDonationDismissUI() {
        let alertController = UIAlertController(
            title: OBALoc(
                "donations.donations_dismiss_alert.title",
                value: "Please don't dismiss this request",
                comment: "Title of the alert that appears when the user chooses to dismiss the donations request UI on a stop page"
            ),
            message: OBALoc(
                "donations.donations_dismiss_alert.message",
                value: "OneBusAway is a volunteer-run organization with almost no funding. We need your help to keep this app running.",
                comment: "Body of the alert that appears when the user chooses to dismiss the donations request UI on a stop page"
            ),
            preferredStyle: .actionSheet
        )

        alertController.addAction(
            title: OBALoc(
                "donations.donations_dismiss_alert.button_dismiss",
                value: "I Don't Want to Help Right Now",
                comment: "Dismiss button on the alert"
            ),
            style: .destructive
        ) { _ in
            self.application.donationsManager.dismissDonationsRequests()
            self.refresh()
        }

        alertController.addAction(
            title: OBALoc(
                "donations.donations_dismiss_alert.button_remind_later",
                value: "Remind Me Later",
                comment: "A button that prompts the system to remind them to donate later."
            ),
            style: .default
        ) { _ in
            self.application.donationsManager.remindUserLater()
            self.refresh()
        }

        alertController.addAction(title: Strings.cancel, style: .cancel, handler: nil)

        present(alertController, animated: true)
    }

    // MARK: - Data/Stop Arrivals

    private var stopArrivalsSection: [OBAListViewSection] {
        guard let stopArrivals = self.stopArrivals else { return [] }
        var sections: [OBAListViewSection] = []

        if stopPreferences.sortType == .time {
            let arrDeps: [ArrivalDeparture]
            if isListFiltered {
                arrDeps = stopArrivals.arrivalsAndDepartures.filter(preferences: stopPreferences)
            } else {
                arrDeps = stopArrivals.arrivalsAndDepartures
            }
            sections = [sectionForGroup(groupRoute: nil, arrDeps: arrDeps)]
        } else {
            let groups = stopArrivals.arrivalsAndDepartures.group(preferences: stopPreferences, filter: isListFiltered).localizedStandardCompare()
            // Regardless of the provided `showSectionHeader`, if stops are grouped by route, we will always show the section header.
            sections = groups.map { sectionForGroup(groupRoute: $0.route, arrDeps: $0.arrivalDepartures) }
        }

        return sections
    }

    private func arrivalDepartureItem(for arrivalDeparture: ArrivalDeparture) -> ArrivalDepartureItem {
        let alarmAvailable = canCreateAlarm(for: arrivalDeparture)
        let deepLinkingAvailable = application.features.deepLinking == .running
        let highlightTimeOnDisplay = shouldHighlight(arrivalDeparture: arrivalDeparture)

        let onSelectAction: OBAListViewAction<ArrivalDepartureItem> = { [unowned self] item in self.didSelectArrivalDepartureItem(item) }
        let addAlarmAction: OBAListViewAction<ArrivalDepartureItem> = { [unowned self] item in self.addAlarm(viewModel: item) }
        let bookmarkAction: OBAListViewAction<ArrivalDepartureItem> = { [unowned self] item in self.addBookmark(viewModel: item) }
        let shareAction: OBAListViewAction<ArrivalDepartureItem>    = { [unowned self] item in self.shareTripStatus(viewModel: item) }

        return ArrivalDepartureItem(
            arrivalDeparture: arrivalDeparture,
            isAlarmAvailable: alarmAvailable,
            isDeepLinkingAvailable: deepLinkingAvailable,
            highlightTimeOnDisplay: highlightTimeOnDisplay,
            onSelectAction: onSelectAction,
            alarmAction: addAlarmAction,
            bookmarkAction: bookmarkAction,
            shareAction: shareAction)
    }

    /// - parameter groupRoute: If `groupRoute` is `nil`, this section will also include a "Load More" button at the end of its contents.
    func sectionForGroup(groupRoute: Route?, arrDeps: [ArrivalDeparture]) -> OBAListViewSection {
        let sectionID: String
        let sectionName: String?
        if let groupRoute = groupRoute {
            sectionID = groupRoute.id
            sectionName = groupRoute.longName ?? groupRoute.shortName
        } else {
            sectionID = "all"
            sectionName = OBALoc("stop_controller.arrival_departure_header", value: "Arrivals and Departures", comment: "A header for the arrivals and departures section of the stop controller.")
        }

        let arrDepItems = arrDeps.map { arrivalDepartureItem(for: $0) }

        var items = arrDepItems
            .sorted(by: \.arrivalDepartureDate)
            .map { $0.typeErased }
        addWalkTimeRow(to: &items)

        if groupRoute == nil {
            items.append(contentsOf: loadMoreItems)
        }

        return listViewSection(for: .arrivalDepartures(suffix: sectionID), title: sectionName, items: items)
    }

    /// Tracks arrival/departure times for `ArrivalDeparture`s.
    private var arrivalDepartureTimes = ArrivalDepartureTimes()

    // ^^^ note: I don't see any reason to destroy outmoded data. The size of an individual key/value pair
    //           is measured in bytes, and the lifecycle of this controller is quite short. If/when the
    //           lifecycle of a StopViewController is ever measured in days or weeks, then we should
    //           revisit this decision.

    func arrivalDeparture(forViewModel viewModel: ArrivalDepartureItem) -> ArrivalDeparture? {
        return stopArrivals?.arrivalsAndDepartures.filter({ $0.id == viewModel.arrivalDepartureID }).first
    }

    // MARK: Actions

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

        let menuProvider: OBAListViewMenuActions.MenuProvider = { [unowned self] _ in
            var actions = [UIAction]()

            if viewModel.isAlarmAvailable {
                let alarm = UIAction(title: Strings.addAlarm, image: Icons.addAlarm) { [unowned self] _ in
                    self.addAlarm(viewModel: viewModel)
                }
                actions.append(alarm)
            }

            let addBookmark = UIAction(title: Strings.addBookmark, image: Icons.addBookmark) { [unowned self] _ in
                self.addBookmark(viewModel: viewModel)
            }
            actions.append(addBookmark)

            let shareTrip = UIAction(title: Strings.shareTrip, image: UIImage(systemName: "square.and.arrow.up")) { [unowned self] _ in
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
        self.previewingVC = (viewModel.id, vc)
        return vc
    }

    private func performPreviewStopArrival(_ viewModel: ArrivalDepartureItem) {
        if let previewingVC = self.previewingVC,
           previewingVC.identifier == viewModel.id,
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
        return listSection(serviceAlerts: alerts, showSectionTitle: true, sectionID: ListSections.serviceAlerts.sectionID)
    }

    // MARK: - Data/Load More
    private var shouldScrollToBottomOfArrivalsDeparuresOnDataLoad = false
    private var loadMoreItems: [AnyOBAListViewItem] {
        var items: [AnyOBAListViewItem] = []

        if let error = operationError {
            items.append(ErrorCaptionItem(error: error).typeErased)
        }

        let loadMoreButton = MessageButtonItem(asLoadMoreButtonWithID: UUID().uuidString, showActivityIndicatorOnSelect: true) { [weak self] _ in
            self?.shouldScrollToBottomOfArrivalsDeparuresOnDataLoad = true
            self?.loadMoreDepartures()
        }
        items.append(loadMoreButton.typeErased)

        return items
    }

    fileprivate var dataAttributionSection: OBAListViewSection {
        let agencies = Formatters.formattedAgenciesForRoutes(self.stop!.routes)
        let dataAttributionStringFormat = OBALoc("stop_controller.data_attribution_format", value: "Data provided by %@", comment: "A string listing the data providers (agencies) for this stop's data. It contains one or more providers separated by commas. e.g. Data provided by King County Metro, Sound Transit")

        let dataDateRangeBeforeTime = Date().addingTimeInterval(Double(minutesBefore) * -60.0)
        let dataDateRangeAfterTime = Date().addingTimeInterval(Double(minutesAfter) * 60.0)
        let dataDateRangeText = application.formatters.formattedDateRange(from: dataDateRangeBeforeTime, to: dataDateRangeAfterTime)

        let dataAttribution = FootnoteItem(text: String(format: dataAttributionStringFormat, agencies), subtitle: dataDateRangeText)

        var section = listViewSection(for: .dataAttribution, title: nil, items: [dataAttribution])
        section.configuration.backgroundColor = .clear
        return section
    }

    // MARK: - Data/More Options

    /// Call this method after data has been reloaded in this controller
    private func dataDidReload() {
        listView.applyData(animated: false)
        self.configureTabBarButtons()
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
    public var selectionFeedbackGenerator: UISelectionFeedbackGenerator? = UISelectionFeedbackGenerator()
    public var collapsedSections: Set<OBAListViewSection.ID> = [] {
        didSet {
            didCollapseSection()
        }
    }

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

    /// Helper for creating stop view controller sections. There are a lot of sections in stopviewcontroller,
    /// so sections must be defined in StopViewController.ListSections for safety.
    func listViewSection<Item: OBAListViewItem>(for section: ListSections, title: String?, items: [Item]) -> OBAListViewSection {
        return OBAListViewSection(id: section.sectionID, title: title, contents: items)
    }

    /// The view controller currently being previewed (via context menu).
    /// The identifier is a string (ideally a `UUID`) used when the user commits the context menu to ensure
    /// that the `previewingVC` is actually the view controller that the user committed to.
    var previewingVC: (identifier: UUID, vc: UIViewController)?
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
        Task { @MainActor in
            await AlertPresenter.show(error: error, presentingController: self)
        }
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

        // Use self.presnt because when using application.viewRouter.present(:_),
        // it disables UIActivityViewController's "tap anywhere to dismiss".
        self.present(activityController, animated: true)
    }

    // MARK: - Actions

    /// Reloads data.
    @objc private func refresh() {
        // Debounce this action in order to prevent the user
        // from spamming the server with a ton of requests.
        DispatchQueue.main.debounce(interval: 1.0) { [weak self] in
            guard let self = self else { return }
            Task(priority: .userInitiated) {
                await self.updateData()
            }
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

        let hiddenRoutes = Set(stopPreferences.hiddenRoutes)
        let stopPreferencesView = StopPreferencesWrappedView(stop, initialHiddenRoutes: hiddenRoutes, delegate: self)
            .environment(\.coreApplication, application)
        present(UIHostingController(rootView: stopPreferencesView), animated: true)
    }

    /// Extends the `ArrivalDeparture` time window visualized by this view controller and reloads data.
    private func loadMore(minutes: UInt) {
        minutesAfter += minutes
        Task {
            await updateData()
        }
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

    func stopPreferences(stopID: StopID, updated stopPreferences: StopPreferences) {
        self.stopPreferences = stopPreferences

        if let stop = self.stop, let region = application.currentRegion {
            self.application.stopPreferencesDataStore.set(stopPreferences: stopPreferences, stop: stop, region: region)
        }
    }

    private var isListFiltered: Bool = true {
        didSet {
            dataDidReload()
        }
    }

    // MARK: - Previewable

    private var inPreviewMode = false

    func enterPreviewMode() {
        inPreviewMode = true
    }

    func exitPreviewMode() {
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
