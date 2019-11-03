//
//  StopViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/27/19.
//

import UIKit
import AloeStackView
import SVProgressHUD
import OBAKitCore
import CoreLocation

/// This is the core view controller for displaying information about a transit stop.
///
/// Specifically, `StopViewController` provides you with information about upcoming
/// arrivals and departures at this stop, along with the ability to create push
/// notification 'alarms' and bookmarks, view information about the location of a
/// particular vehicle, and report problems with a trip.
public class StopViewController: UIViewController,
    AlarmBuilderDelegate,
    AloeStackTableBuilder,
    BookmarkEditorDelegate,
    ModalDelegate,
    StopArrivalDelegate,
    StopPreferencesDelegate {

    private let kUseDebugColors = false

    lazy var stackView: AloeStackView = {
        let stack = AloeStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addSubview(refreshControl)
        stack.rowInset = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        stack.alwaysBounceVertical = true
        stack.backgroundColor = ThemeColors.shared.systemBackground
        return stack
    }()

    private let refreshControl = UIRefreshControl()

    let application: Application

    let stopID: String

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

    // MARK: - Subviews

    /// The header displayed at the top of the controller
    ///
    /// - Note: Not used with floating panel navigation.
    private lazy var stopHeader = StopHeaderViewController(application: application)

    /// Provides storage for actively-used `StopArrivalView`s.
    private var stopArrivalViews = [TripIdentifier: StopArrivalView]()

    /// A button that the user can tap on to load more `ArrivalDeparture` objects.
    ///
    /// - Note: See `loadMore()` for more details.
    private lazy var loadMoreButton: UIButton = {
        let loadMoreButton = UIButton(type: .system)
        loadMoreButton.setTitle(NSLocalizedString("stop_controller.load_more_button", value: "Load More", comment: "Load More button"), for: .normal)
        loadMoreButton.addTarget(self, action: #selector(loadMoreDepartures), for: .touchUpInside)
        return loadMoreButton
    }()

    /// A label that is displayed below the `loadMoreButton` when the time window visualized by this view controller is greater than the default.
    private lazy var timeframeLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.textAlignment = .center
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textColor = ThemeColors.shared.secondaryLabel

        return label
    }()

    // MARK: - Data

    /// The data-loading operation for this controller.
    var operation: StopArrivalsModelOperation?

    /// The stop displayed by this controller.
    var stop: Stop? {
        didSet {
            guard let stop = stop else { return }
            performStopConfiguration(stop)
        }
    }

    private func performStopConfiguration(_ stop: Stop) {
        if let region = application.currentRegion {
            application.userDataStore.addRecentStop(stop, region: region)
        }

        stopHeader.stop = stop
    }

    /// Arrival/Departure data for this stop.
    var stopArrivals: StopArrivals? {
        didSet {
            if stopArrivals != nil {
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

        performStopConfiguration(stop)
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
    public init(application: Application, stopID: String) {
        self.application = application
        self.stopID = stopID
        self.stopPreferences = application.stopPreferencesDataStore.preferences(stopID: stopID, region: application.currentRegion!)

        super.init(nibName: nil, bundle: nil)

        stackView.showsVerticalScrollIndicator = true
        stackView.alwaysBounceVertical = true

        Timer.scheduledTimer(timeInterval: StopViewController.defaultTimerReloadInterval / 2.0, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)

        navigationItem.backBarButtonItem = UIBarButtonItem.backButton
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        reloadTimer.invalidate()
        operation?.cancel()
    }

    // MARK: - UIViewController Overrides

    public override func viewDidLoad() {
        super.viewDidLoad()

        if kUseDebugColors {
            stackView.backgroundColor = .yellow
        }

        prepareChildController(stopHeader) {
            stackView.addRow(stopHeader.view, hideSeparator: true, insets: .zero)
        }

        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)

        view.addSubview(stackView)
        view.addSubview(fakeToolbar)

        let toolbarHeight: CGFloat = 44.0

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            fakeToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fakeToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fakeToolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            fakeToolbar.heightAnchor.constraint(greaterThanOrEqualToConstant: toolbarHeight),
            fakeToolbar.stackWrapper.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        var inset = stackView.contentInset

        inset.bottom = toolbarHeight + view.safeAreaInsets.bottom
        stackView.contentInset = inset
        stackView.scrollIndicatorInsets = inset
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        application.isIdleTimerDisabled = true

        if stopArrivals != nil {
            beginUserActivity()
        }

        updateData()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        application.isIdleTimerDisabled = false
    }

    // MARK: - Bottom Toolbar

    private lazy var refreshButton = buildToolbarButton(title: Strings.refresh, image: Icons.refresh, target: self, action: #selector(refresh))

    private lazy var bookmarkButton = buildToolbarButton(title: Strings.bookmark, image: Icons.favorited, target: self, action: #selector(addBookmark(sender:)))

    private lazy var filterButton = buildToolbarButton(title: Strings.filter, image: Icons.filter, target: self, action: #selector(filter))

    private func buildToolbarButton(title: String, image: UIImage, target: Any, action: Selector) -> UIButton {
        let button = ProminentButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setImage(image, for: .normal)
        button.addTarget(target, action: action, for: .touchUpInside)
        NSLayoutConstraint.activate([button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40.0)])
        return button
    }

    private lazy var fakeToolbar: FakeToolbar = {
        let toolbar = FakeToolbar(toolbarItems: [refreshButton, bookmarkButton, filterButton])
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        return toolbar
    }()

    // MARK: - NSUserActivity

    /// Creates and assigns an `NSUserActivity` object corresponding to this stop.
    private func beginUserActivity() {
        guard let stop = stop,
              let region = application.regionsService.currentRegion else { return }

        self.userActivity = application.userActivityBuilder.userActivity(for: stop, region: region)
    }

    // MARK: - Data Loading

    /// Reloads data from the server and repopulates the UI once it finishes loading.
    func updateData() {
        operation?.cancel()

        guard let modelService = application.restAPIModelService else { return }

        title = Strings.updating

        let op = modelService.getArrivalsAndDeparturesForStop(id: stopID, minutesBefore: minutesBefore, minutesAfter: minutesAfter)
        op.then { [weak self] in
            guard let self = self else { return }

            self.lastUpdated = Date()
            self.stopArrivals = op.stopArrivals
            self.refreshControl.endRefreshing()
            self.updateTitle()

            if let arrivals = op.stopArrivals, arrivals.arrivalsAndDepartures.count == 0 {
                self.extendLoadMoreWindow()
            }
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

    /// Call this method after data has been reloaded in this controller
    private func dataDidReload() {
        guard let stopArrivals = stopArrivals else { return }

        // Remove all of the rows except the header.
        let rows = stackView.getAllRows()
        stackView.removeRows(Array(rows[1...]))

        if stopPreferences.hasHiddenRoutes {
            stackView.addRow(filterToggleControl)
            stackView.hideSeparator(forRow: filterToggleControl)
        }

        if stopPreferences.sortType == .time {
            if isListFiltered {
                addToStack(arrivalDepartures: stopArrivals.arrivalsAndDepartures.filter(preferences: stopPreferences))
            }
            else {
                addToStack(arrivalDepartures: stopArrivals.arrivalsAndDepartures)
            }
        }
        else {
            let groups = stopArrivals.arrivalsAndDepartures.group(preferences: stopPreferences, filter: isListFiltered).localizedStandardCompare()

            for g in groups {
                addTableHeaderToStack(headerText: g.route.longName ?? g.route.shortName)
                addToStack(arrivalDepartures: g.arrivalDepartures)
            }
        }

        // Load More and Timeframe
        stackView.addRow(loadMoreButton, hideSeparator: true)
        displayTimeframeLabel()

        // More Options
        addMoreOptionsTableRows()
    }

    // MARK: - UI Builders

    private func addToStack(arrivalDepartures: [ArrivalDeparture]) {
        // Walking Time and Arrival/Departures
        var walkingTimeInserted = false

        for arrDep in arrivalDepartures {
            if !walkingTimeInserted {
                walkingTimeInserted = addWalkingTimeRow(before: arrDep)
            }

            addStopArrivalView(for: arrDep, hideSeparator: false)
        }
    }

    private func addWalkingTimeRow(before arrivalDeparture: ArrivalDeparture) -> Bool {
        let interval = arrivalDeparture.arrivalDepartureDate.timeIntervalSinceNow

        guard
            let currentLocation = application.locationService.currentLocation,
            let stopLocation = stop?.location,
            let walkingTime = WalkingDirections.travelTime(from: currentLocation, to: stopLocation),
            interval >= walkingTime
        else { return false }

        if let lastRow = stackView.lastRow {
            stackView.removeRow(lastRow)
            stackView.addRow(lastRow, hideSeparator: true)
        }

        let walkTimeRow = WalkTimeView.autolayoutNew()
        walkTimeRow.formatters = application.formatters
        walkTimeRow.set(distance: currentLocation.distance(from: stopLocation), timeToWalk: walkingTime)

        stackView.addRow(walkTimeRow, hideSeparator: true)
        stackView.setInset(forRow: walkTimeRow, inset: .zero)

        return true
    }

    private func addNearbyStopsTableRow(stop: Stop) {
        let row = DefaultTableRowView(title: NSLocalizedString("stops_controller.nearby_stops", value: "Nearby Stops", comment: "Title of the row that will show stops that are near this one."), accessoryType: .disclosureIndicator)
        addGroupedTableRowToStack(row, isLastRow: false) { [weak self] _ in
            guard
                let self = self
            else { return }

            let nearbyController = NearbyStopsViewController(coordinate: stop.coordinate, application: self.application)
            self.application.viewRouter.navigate(to: nearbyController, from: self)
        }
    }

    private func addAppleMapsTableRow(_ coordinate: CLLocationCoordinate2D) {
        let appleMaps = DefaultTableRowView(title: NSLocalizedString("stops_controller.walking_directions_apple", value: "Walking Directions (Apple Maps)", comment: "Button that launches Apple's maps.app with walking directions to this stop"), accessoryType: .disclosureIndicator)
        stackView.addRow(appleMaps)
        stackView.setTapHandler(forRow: appleMaps) { [weak self] _ in
            guard
                let self = self,
                let url = AppInterop.appleMapsWalkingDirectionsURL(coordinate: coordinate)
                else { return }

            self.application.open(url, options: [:], completionHandler: nil)
        }
    }

    private func addGoogleMapsTableRow(_ coordinate: CLLocationCoordinate2D) {
        guard
            let url = AppInterop.googleMapsWalkingDirectionsURL(coordinate: coordinate),
            application.canOpenURL(url)
        else { return }

        let row = DefaultTableRowView(title: NSLocalizedString("stops_controller.walking_directions_google", value: "Walking Directions (Google Maps)", comment: "Button that launches Google Maps with walking directions to this stop"), accessoryType: .disclosureIndicator)
        stackView.addRow(row, hideSeparator: false)
        stackView.setTapHandler(forRow: row) { [weak self] _ in
            guard let self = self else { return }
            self.application.open(url, options: [:], completionHandler: nil)
        }
    }

    private func addMoreOptionsTableRows() {
        if let stop = stop {
            addNearbyStopsTableRow(stop: stop)

            addAppleMapsTableRow(stop.coordinate)

            #if !targetEnvironment(simulator)
            addGoogleMapsTableRow(stop.coordinate)
            #endif
        }

        // Report Problem
        let reportProblem = DefaultTableRowView(title: NSLocalizedString("stops_controller.report_problem", value: "Report a Problem", comment: "Button that launches the 'Report Problem' UI."), accessoryType: .disclosureIndicator)
        stackView.addRow(reportProblem)
        stackView.setTapHandler(forRow: reportProblem) { [weak self] _ in
            guard let self = self else { return }
            self.showReportProblem()
        }
    }

    /// Adds a `StopArrivalView` to the `stackView` that corresponds to `arrivalDeparture`.
    /// - Parameter arrivalDeparture: The model object that generates a `StopArrivalView` row.
    /// - Parameter hideSeparator: Whether or not the bottom separator view should be hidden.
    private func addStopArrivalView(for arrivalDeparture: ArrivalDeparture?, hideSeparator: Bool) {
        guard let arrivalDeparture = arrivalDeparture else { return }

        let arrivalView: StopArrivalView!

        if let a = stopArrivalViews[arrivalDeparture.tripID] {
            arrivalView = a
        }
        else {
            arrivalView = StopArrivalView.autolayoutNew()
            arrivalView.formatters = application.formatters
            arrivalView.showActionsButton = true
            arrivalView.delegate = self

            stopArrivalViews[arrivalDeparture.tripID] = arrivalView
        }

        stackView.addRow(arrivalView, hideSeparator: hideSeparator)
        stackView.setTapHandler(forRow: arrivalView) { [weak self] _ in
            guard let self = self else { return }

            let tripController = TripViewController(application: self.application, arrivalDeparture: arrivalDeparture)
            self.application.viewRouter.navigate(to: tripController, from: self)
        }

        arrivalView.arrivalDeparture = arrivalDeparture
    }

    /// Creates a label that depicts the arrival/departure timeframe that the user is viewing, and adds it to the `stackView`.
    private func displayTimeframeLabel() {
        // We are showing a wider range of time, which means we should show a label
        // that depicts the timeframe that is being viewed.
        let beforeTime = Date().addingTimeInterval(Double(minutesBefore) * -60.0)
        let afterTime = Date().addingTimeInterval(Double(minutesAfter) * 60.0)
        timeframeLabel.text = application.formatters.formattedDateRange(from: beforeTime, to: afterTime)
        stackView.addRow(timeframeLabel, hideSeparator: false)
    }

    // MARK: - Stop Arrival Actions

    public func actionsButtonTapped(arrivalDeparture: ArrivalDeparture) {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if canCreateAlarm(for: arrivalDeparture) {
            actionSheet.addAction(title: NSLocalizedString("stop_controller.add_alarm", value: "Add Alarm", comment: "Action sheet button title for adding an alarm.")) { [weak self] _ in
                guard let self = self else { return }
                self.addAlarm(arrivalDeparture: arrivalDeparture)
            }
        }

        actionSheet.addAction(title: NSLocalizedString("stop_controller.add_bookmark", value: "Add Bookmark", comment: "Action sheet button title for adding a bookmark")) { [weak self] _ in
            guard let self = self else { return }
            self.addBookmark(arrivalDeparture: arrivalDeparture)
        }

        actionSheet.addAction(UIAlertAction.cancelAction)

        application.viewRouter.present(actionSheet, from: self)
    }

    // MARK: - Alarms

    private func canCreateAlarm(for arrivalDeparture: ArrivalDeparture) -> Bool {
        // abxoxo - there are other constraints on creating alarms. What are they?
        // express them here!
        guard
            application.obacoService != nil,
            application.pushService != nil
        else {
            return false
        }

        return true
    }

    private var alarmBuilder: AlarmBuilder?

    func addAlarm(arrivalDeparture: ArrivalDeparture) {
        alarmBuilder = AlarmBuilder(arrivalDeparture: arrivalDeparture, application: application, delegate: self)
        alarmBuilder?.showBulletin(above: self)
    }

    func alarmBuilderStartedRequest(_ alarmBuilder: AlarmBuilder) {
        SVProgressHUD.show()
    }

    func alarmBuilder(_ alarmBuilder: AlarmBuilder, alarmCreated alarm: Alarm) {
        let message = NSLocalizedString("stop_controller.alarm_created_message", value: "Alarm created", comment: "A message that appears when a user's alarm is created.")
        SVProgressHUD.showSuccessAndDismiss(message: message)
    }

    func alarmBuilder(_ alarmBuilder: AlarmBuilder, error: Error) {
        SVProgressHUD.dismiss()
        AlertPresenter.show(error: error, presentingController: self)
    }

    // MARK: - Bookmarks

    private func addBookmark(arrivalDeparture: ArrivalDeparture) {
        let bookmarkController = EditBookmarkViewController(application: application, arrivalDeparture: arrivalDeparture, bookmark: nil, delegate: self)
        let navigation = UINavigationController(rootViewController: bookmarkController)

        application.viewRouter.present(navigation, from: self)
    }

    // MARK: - Bookmark Editor

    func bookmarkEditorCancelled(_ viewController: UIViewController) {
        viewController.dismiss(animated: true, completion: nil)
    }

    func bookmarkEditor(_ viewController: UIViewController, editedBookmark bookmark: Bookmark) {
        // abxoxo todo - show some sort of status message when a bookmark is added or changed.
        viewController.dismiss(animated: true, completion: nil)
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
        application.viewRouter.present(navigation, from: self, isModalInPresentation: true)
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
        application.viewRouter.present(navigation, from: self, isModalInPresentation: true)
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

    @objc private func filterToggled() {
        isListFiltered.toggle()
    }

    private let filterToggleControl: UISegmentedControl = {
        let segment = UISegmentedControl.autolayoutNew()

        segment.insertSegment(withTitle: NSLocalizedString("stop_controller.filter_toggle.all_departures", value: "All Departures", comment: "Segmented control item: show all departures"), at: 0, animated: false)
        segment.insertSegment(withTitle: NSLocalizedString("stop_controller.filter_toggle.filtered_departures", value: "Filtered Departures", comment: "Segmented control item: show filtered departures"), at: 1, animated: false)

        segment.selectedSegmentIndex = 1

        segment.addTarget(self, action: #selector(filterToggled), for: .valueChanged)

        return segment
    }()
}
