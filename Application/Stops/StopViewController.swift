//
//  StopViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/27/19.
//

import UIKit
import AloeStackView
import FloatingPanel

/// This is the core view controller for displaying information about a transit stop.
///
/// Specifically, `StopViewController` provides you with information about upcoming
/// arrivals and departures at this stop, along with the ability to create push
/// notification 'alarms' and bookmarks, view information about the location of a
/// particular vehicle, and report problems with a trip.
public class StopViewController: UIViewController {
    private let kUseDebugColors = false

    lazy var stackView: AloeStackView = {
        let stack = AloeStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addSubview(refreshControl)
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
        loadMoreButton.addTarget(self, action: #selector(loadMore), for: .touchUpInside)
        return loadMoreButton
    }()

    /// A label that is displayed below the `loadMoreButton` when the time window visualized by this view controller is greater than the default.
    private lazy var timeframeLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.textAlignment = .center
        label.font = application.theme.fonts.footnote
        label.textColor = application.theme.colors.subduedText

        return label
    }()

    // MARK: - Data

    /// The data-loading operation for this controller.
    var operation: StopArrivalsModelOperation?

    /// The stop displayed by this controller.
    var stop: Stop? {
        didSet {
            guard let stop = stop else { return }

            application.userDataStore.addRecentStop(stop)
            stopHeader.stop = stop
        }
    }

    /// Arrival/Departure data for this stop.
    var stopArrivals: StopArrivals? {
        didSet {
            dataWillReload()

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

        super.init(nibName: nil, bundle: nil)

        hidesBottomBarWhenPushed = true

        toolbarItems = buildToolbarItems()

        configureCurrentThemeBehaviors()

        Timer.scheduledTimer(timeInterval: StopViewController.defaultTimerReloadInterval / 2.0, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        reloadTimer.invalidate()
        operation?.cancel()
    }

    // MARK: - Private Init Helpers

    /// Creates an array of toolbar items used to populate the toolbar on this view controller.
    private func buildToolbarItems() -> [UIBarButtonItem] {
        let refreshButton = UIBarButtonItem(title: Strings.refresh, style: .plain, target: self, action: #selector(refresh))
        refreshButton.image = Icons.refresh

        let bookmarkButton = UIBarButtonItem(title: Strings.bookmark, style: .plain, target: self, action: #selector(addBookmark))
        bookmarkButton.image = Icons.favorited

        let filterButton = UIBarButtonItem(title: Strings.filter, style: .plain, target: self, action: #selector(filter))
        filterButton.image = Icons.filter

        return [filterButton, UIBarButtonItem.flexibleSpace, bookmarkButton, UIBarButtonItem.flexibleSpace, refreshButton]
    }

    /// Configures the UI of this view controller based on whether we're using floating panel navigation or regular navigation.
    private func configureCurrentThemeBehaviors() {
        if application.theme.behaviors.useFloatingPanelNavigation {
            stackView.showsVerticalScrollIndicator = false
            stackView.alwaysBounceVertical = false
            stackView.rowInset = UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 0)
        }
        else {
            stackView.showsVerticalScrollIndicator = true
            stackView.alwaysBounceVertical = true
            stackView.rowInset = UIEdgeInsets(top: 5, left: 20, bottom: 5, right: 20)
        }
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
        stackView.pinToSuperview(.edges)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        application.isIdleTimerDisabled = true

        if stopArrivals != nil {
            beginUserActivity()
        }

        updateData()

        navigationController?.setToolbarHidden(false, animated: true)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        application.isIdleTimerDisabled = false

        navigationController?.setToolbarHidden(true, animated: true)
    }

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
        }

        self.operation = op
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

    /// Call this method when data is about to reloaded in this controller
    private func dataWillReload() {
        stackView.removeAllRows()
    }

    /// Call this method after data has been reloaded in this controller
    private func dataDidReload() {
        guard let stopArrivals = stopArrivals else {
            return
        }

        stop = stopArrivals.stop

        stackView.addRow(stopHeader.view, hideSeparator: true, insets: .zero)

        for arrDep in stopArrivals.arrivalsAndDepartures {
            addStopArrivalView(for: arrDep, hideSeparator: false)
        }

        stackView.addRow(loadMoreButton, hideSeparator: true)

        if minutesAfter != StopViewController.defaultMinutesAfter {
            // We are showing a wider range of time, which means we should show a label
            // that depicts the timeframe that is being viewed.
            let beforeTime = Date().addingTimeInterval(Double(minutesBefore) * -60.0)
            let afterTime = Date().addingTimeInterval(Double(minutesAfter) * 60.0)
            timeframeLabel.text = application.formatters.formattedDateRange(from: beforeTime, to: afterTime)
            stackView.addRow(timeframeLabel, hideSeparator: true)
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
            stopArrivalViews[arrivalDeparture.tripID] = arrivalView
        }

        stackView.addRow(arrivalView, hideSeparator: hideSeparator)
        arrivalView.arrivalDeparture = arrivalDeparture
    }
}

// MARK: - Actions
extension StopViewController {

    /// Reloads data.
    @objc private func refresh() {
        updateData()
    }

    /// Initiates the 'Add Bookmark' workflow.
    @objc private func addBookmark() {

    }

    /// Initiates the Route Filter workflow.
    @objc private func filter() {

    }

    /// Extends the `ArrivalDeparture` time window visualized by this view controller and reloads data.
    @objc private func loadMore() {
        self.minutesAfter += 30
        updateData()
    }
}
