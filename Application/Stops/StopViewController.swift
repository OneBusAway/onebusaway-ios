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
    var minutesAfter: UInt = 35
    private var lastUpdated: Date?

    // MARK: - Top Content

    lazy var stopHeader = StopHeaderViewController(application: application)

    // MARK: - Bottom Content

    lazy var loadMoreButton: UIButton = {
        let loadMoreButton = UIButton(type: .system)
        loadMoreButton.setTitle(NSLocalizedString("stop_controller.load_more_button", value: "Load More", comment: "Load More button"), for: .normal)
        loadMoreButton.addTarget(self, action: #selector(loadMore), for: .touchUpInside)
        return loadMoreButton
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
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        operation?.cancel()
    }

    // MARK: - Private Init Helpers

    private func buildToolbarItems() -> [UIBarButtonItem] {
        let refreshButton = UIBarButtonItem(title: Strings.refresh, style: .plain, target: self, action: #selector(refresh))
        refreshButton.image = Icons.refresh

        let bookmarkButton = UIBarButtonItem(title: Strings.bookmark, style: .plain, target: self, action: #selector(addBookmark))
        bookmarkButton.image = Icons.favorited

        let filterButton = UIBarButtonItem(title: Strings.filter, style: .plain, target: self, action: #selector(filter))
        filterButton.image = Icons.filter

        return [filterButton, UIBarButtonItem.flexibleSpace, bookmarkButton, UIBarButtonItem.flexibleSpace, refreshButton]
    }

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
    }

    private func addStopArrivalView(for arrivalDeparture: ArrivalDeparture?, hideSeparator: Bool) {
        guard let arrivalDeparture = arrivalDeparture else { return }

        let a = StopArrivalView.autolayoutNew()
        stackView.addRow(a, hideSeparator: hideSeparator)
        a.arrivalDeparture = arrivalDeparture
    }
}

// MARK: - Actions
extension StopViewController {
    @objc private func refresh() {
        updateData()
    }

    @objc private func addBookmark() {

    }

    @objc private func filter() {

    }

    @objc private func loadMore() {
        self.minutesAfter += 30
        updateData()
    }
}
