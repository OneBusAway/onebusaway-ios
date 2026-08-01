//
//  TripPageViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import ActivityKit
import Combine
import SwiftUI
import OBAKitCore

/// Hosts `TripPageView` and owns every reach into `Application` the page needs —
/// navigation, alarms, bookmarks, schedules, Live Activities.
///
/// Deliberately map-free. `TripViewController`, which this replaces, owned a
/// full-screen `MKMapView` and added its own floating panel as a child; pushed
/// into the stop sheet that nests a panel inside a panel. Keeping the map out of
/// here is what lets the same page be pushed into a sheet over the map tab's map
/// and, later, into a standalone host that supplies its own.
final class TripPageViewController: UIHostingController<TripPageView>,
    AppContext,
    AlarmBuilderDelegate,
    BookmarkEditorDelegate,
    Idleable {

    public let application: Application
    let viewModel: TripViewModel

    /// The name of the screen this was pushed from, shown beside the back button.
    private let originTitle: String?

    private var cancellables = Set<AnyCancellable>()
    private var alarmBuilder: AlarmBuilder?
    private var alarmBuilderDeparture: ArrivalDeparture?
    private var isTrackingLiveActivity = false

    public var idleTimerFailsafe: Timer?

    init(application: Application, tripConvertible: TripConvertible, originTitle: String? = nil) {
        self.application = application
        self.originTitle = originTitle
        self.viewModel = TripViewModel(application: application, tripConvertible: tripConvertible)

        // The page's actions capture `self`, which doesn't exist until after
        // `super.init`. Seed with the inert default set and replace immediately.
        super.init(rootView: TripPageView(viewModel: viewModel, originTitle: originTitle, actions: TripPageActions()))

        render()
    }

    convenience init(application: Application, arrivalDeparture: ArrivalDeparture, originTitle: String? = nil) {
        self.init(
            application: application,
            tripConvertible: TripConvertible(arrivalDeparture: arrivalDeparture),
            originTitle: originTitle
        )
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // The page draws its own back row, so a navigation bar here would be a
        // second one — and inside the sheet it would impose a top safe area that
        // eats the sheet's scarce height.
        navigationController?.setNavigationBarHidden(true, animated: false)

        // The gates the action bar renders from (`canAlarm` in particular) are
        // derived from the departure, which the 30s refresh replaces. Without
        // this the bar would keep offering an alarm for a bus that has since
        // come inside the one-minute floor.
        viewModel.$tripConvertible
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        disableIdleTimer()
        viewModel.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        enableIdleTimer()
        viewModel.deactivate()
    }

    // MARK: - Rendering

    private var departure: ArrivalDeparture? { viewModel.tripConvertible.arrivalDeparture }

    /// Rebuilds the value-typed inputs the page can't observe for itself. The
    /// view model is observed directly by the view, so this is only for the
    /// action gates and the two pieces of state this controller owns.
    private func render() {
        rootView = TripPageView(
            viewModel: viewModel,
            originTitle: originTitle,
            actions: makeActions(),
            hasAlarm: false,
            isTrackingLiveActivity: isTrackingLiveActivity
        )
    }

    private func makeActions() -> TripPageActions {
        var actions = TripPageActions()

        actions.canSchedule = application.currentRegion?.supportsScheduleForRoute ?? true
        actions.canAlarm = departure.map(canCreateAlarm) ?? false
        // A Live Activity reports a countdown to a stop. Without a departure
        // there is no stop and nothing to count down to.
        actions.canStartLiveActivity = departure != nil && ActivityAuthorizationInfo().areActivitiesEnabled

        actions.onBack = { [weak self] in
            guard let self else { return }
            navigationController?.popViewController(animated: true)
        }
        actions.onSelectStop = { [weak self] stopID in
            guard let self else { return }
            application.viewRouter.navigateTo(stopID: stopID, from: self)
        }
        actions.onBookmark = { [weak self] in self?.showBookmarkEditor() }
        actions.onSchedule = { [weak self] in self?.showSchedule() }
        actions.onAlarm = { [weak self] in self?.showAlarmPicker() }
        actions.onLiveActivity = { [weak self] in self?.startLiveActivity() }

        return actions
    }

    /// Mirrors `StopViewModel.canCreateAlarm(for:)`. Alarms are an Obaco push
    /// feature, and one that can't be scheduled for a bus already inside the
    /// one-minute floor.
    private func canCreateAlarm(for departure: ArrivalDeparture) -> Bool {
        application.features.obaco == .running
            && application.features.push == .running
            && departure.arrivalDepartureMinutes > 1
    }

    // MARK: - Actions

    private func showSchedule() {
        let scheduleVC = ScheduleForRouteViewController(
            routeID: viewModel.tripConvertible.trip.routeID,
            application: application
        )
        present(scheduleVC, animated: true)
    }

    private func showBookmarkEditor() {
        guard let departure else { return }
        let editor = EditBookmarkViewController(application: application, arrivalDeparture: departure, bookmark: nil, delegate: self)
        application.viewRouter.present(UINavigationController(rootViewController: editor), from: self)
    }

    private func showAlarmPicker() {
        // Re-checked here, not just at render time: the gate is recomputed on the
        // 30s refresh, so a departure can slip inside the one-minute floor while
        // the button is still on screen.
        guard let departure, canCreateAlarm(for: departure) else { return }

        alarmBuilderDeparture = departure
        alarmBuilder = AlarmBuilder(arrivalDeparture: departure, application: application, delegate: self)
        alarmBuilder?.showBulletin(above: self)
    }

    // MARK: - AlarmBuilderDelegate

    func alarmBuilderStartedRequest(_ alarmBuilder: AlarmBuilder) {
        ProgressHUD.show()
    }

    func alarmBuilder(_ alarmBuilder: AlarmBuilder, alarmCreated alarm: Alarm) {
        if alarmBuilder.trackOnLockScreen {
            startLiveActivity()
        }

        let message = OBALoc("stop_controller.alarm_created_message", value: "Alarm created", comment: "A message that appears when a user's alarm is created.")
        ProgressHUD.showSuccessAndDismiss(message: message)
    }

    func alarmBuilder(_ alarmBuilder: AlarmBuilder, error: Error) {
        ProgressHUD.dismiss()
        Task { @MainActor in
            await AlertPresenter.show(error: error, presentingController: self)
        }
    }

    // MARK: - BookmarkEditorDelegate

    func bookmarkEditorCancelled(_ viewController: UIViewController) {
        viewController.dismiss(animated: true)
    }

    func bookmarkEditor(_ viewController: UIViewController, editedBookmark bookmark: Bookmark, isNewBookmark: Bool) {
        viewController.dismiss(animated: true)
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        guard let departure, ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let staticData = TripAttributes.StaticData(
            routeShortName: departure.routeShortName,
            routeHeadsign: departure.tripHeadsign ?? "",
            stopID: departure.stopID,
            routeColorHex: departure.route.color?.toHex(),
            regionID: application.currentRegion?.regionIdentifier ?? 0
        )

        // The same trip can be started from here, the stop page, and the
        // bookmarks list. Without this guard one stop ends up with two Lock
        // Screen cards and two OBACloud push registrations.
        if Activity<TripAttributes>.running(matching: staticData) != nil {
            Logger.info("Live Activity already running for stop \(staticData.stopID) route \(staticData.routeShortName); not starting a duplicate.")
            isTrackingLiveActivity = true
            render()
            return
        }

        let contentState = TripAttributes.ContentState(arrivals: [
            TripAttributes.ContentState.ArrivalInfo(
                departureTime: Int(departure.arrivalDepartureDate.timeIntervalSince1970),
                scheduleStatus: .init(departure.scheduleStatus),
                scheduleDeviation: departure.deviationFromScheduleInMinutes * 60,
                isArrival: departure.arrivalDepartureStatus == .arriving
            )
        ])

        do {
            let activity = try Activity.request(
                attributes: TripAttributes(staticData: staticData),
                content: .init(state: contentState, staleDate: nil),
                pushType: .token
            )
            application.liveActivityTracker.track(activity: activity, metadata: .init(departure))
            Logger.info("Started Live Activity with ID: \(activity.id)")
            isTrackingLiveActivity = true
            render()
        } catch {
            Logger.error("Failed to start Live Activity: \(error)")
            showLiveActivityErrorAlert()
        }
    }
}
