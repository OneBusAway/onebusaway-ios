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
import CoreLocation
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
    Idleable,
    StopSheetCollapsibleContent,
    StopSheetSelfChromedContent {

    public let application: Application
    let viewModel: TripViewModel

    /// The name of the screen this was pushed from, shown beside the back button.
    private let originTitle: String?

    private var cancellables = Set<AnyCancellable>()
    private var alarmBuilder: AlarmBuilder?
    private var alarmBuilderDeparture: ArrivalDeparture?
    private var isTrackingLiveActivity = false

    /// `true` while the sheet showing this page sits at its `.tip` detent. Stored rather than
    /// derived so every `render()` — the 30s refresh drives one — rebuilds the page with the
    /// detent the sheet is actually at instead of resetting it to expanded.
    private var isAtTip = false

    let providesOwnSheetChrome = true

    /// The page is grouped-gray, not `.systemBackground`, so the sheet has to paint the
    /// strip behind its grabber to match or it reads as a white bar across the top.
    let sheetSurfaceColor: UIColor? = .systemGroupedBackground

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
        //
        // Set here for hosts that don't manage the bar themselves, and answered
        // again through `providesOwnSheetChrome` for the stop sheet, whose
        // presenter re-decides it on every push and would otherwise put the bar
        // straight back.
        navigationController?.setNavigationBarHidden(true, animated: false)

        // Re-render now that there is a `navigationController` to ask. `init`
        // runs before this page is on anyone's stack, so the back row's glyph
        // was built from an unanswerable question — and a modal would have come
        // up wearing a chevron for the first frame.
        render()

        // Everything the map draws, and the gates the action bar renders from,
        // are derived from these three together.
        //
        // Combined rather than three sinks: `@Published` fires in `willSet`, so a
        // sink that reaches back for `viewModel.tripDetails` reads the PREVIOUS
        // value — nil on the first load. Taking all three from the closure's
        // parameters makes that mistake unavailable. (The same trap cost this
        // branch every vehicle on a stop's first load; see
        // `MapViewController.beginRouteFocus`.)
        viewModel.$tripConvertible
            .combineLatest(viewModel.$tripDetails, viewModel.$routePolylineCoordinates)
            .sink { [weak self] convertible, details, shape in
                guard let self else { return }
                publishMapFocus(convertible: convertible, details: details, shape: shape)
                render()
            }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        disableIdleTimer()
        viewModel.start()
        onMapFocusChanged?(mapFocus)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        enableIdleTimer()
        viewModel.deactivate()

        // Only on the way out of the stack. A modal presented over this page
        // (the alarm bulletin, the bookmark editor) also fires this, and giving
        // the map back then would drop the trip while the rider is still on it.
        if isMovingFromParent {
            onMapFocusChanged?(nil)
        }
    }

    // MARK: - Map focus

    /// What the map should be drawing while this page is up. The host decides
    /// which map that is — see `onMapFocusChanged`.
    let mapFocus = TripMapFocus()

    /// Set by whoever owns a map: called with the focus when this page appears
    /// and with `nil` when it leaves the stack.
    var onMapFocusChanged: ((TripMapFocus?) -> Void)?

    private func publishMapFocus(
        convertible: TripConvertible,
        details: TripDetails?,
        shape: [CLLocationCoordinate2D]?
    ) {
        let status = convertible.tripStatus
        let departure = convertible.arrivalDeparture

        let stops = TripStopListModel.make(
            stopTimes: details?.stopTimes ?? [],
            userStopID: departure?.stopID,
            userStopSequence: departure?.stopSequence,
            closestStopID: status?.closestStopID
        ).rows

        mapFocus.apply(
            TripMapFocus.Content(
                tripID: convertible.trip.id,
                routeColor: convertible.trip.route?.color ?? ThemeColors.shared.brand,
                routeType: convertible.trip.route?.routeType ?? .unknown,
                shape: shape ?? [],
                // No status means no reported progress, so the whole shape draws
                // as ahead rather than the map inventing a split point.
                progress: status.flatMap {
                    TripShapeSplit.fraction(
                        distanceAlongTrip: $0.distanceAlongTrip,
                        totalDistanceAlongTrip: $0.totalDistanceAlongTrip
                    )
                },
                stops: stops,
                vehicle: status
            )
        )
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
            backBehavior: backBehavior,
            hasAlarm: false,
            isTrackingLiveActivity: isTrackingLiveActivity,
            isCollapsed: isAtTip
        )
    }

    // MARK: - StopSheetCollapsibleContent

    /// Called by `StopSheetPresenter` whenever the sheet's detent changes. At `.tip` the page
    /// drops its pinned action bar, which is taller than that detent, so the peek shows the back
    /// row naming where the trip was opened from instead of a stranded Live Activity button.
    func setAtTip(_ isAtTip: Bool) {
        guard self.isAtTip != isAtTip else { return }
        self.isAtTip = isAtTip
        rootView.isCollapsed = isAtTip
    }

    // MARK: - Back

    /// Which way out this presentation has. See `TripPageBackBehavior`.
    var backBehavior: TripPageBackBehavior {
        TripPageBackBehavior.forStackDepth(navigationController?.viewControllers.count ?? 0)
    }

    /// Back, resolved against the stack rather than assumed.
    ///
    /// The page is pushed from the Stop page and presented from the map sheet,
    /// and `popViewController` only works for the first — as the root of its own
    /// navigation controller it returns nil and leaves the rider pressing a
    /// button that does nothing.
    private func goBack() {
        switch backBehavior {
        case .pop:
            navigationController?.popViewController(animated: true)
        case .dismiss:
            // UIKit forwards this up to whoever did the presenting, so it takes
            // the wrapping navigation controller with it. The Done button
            // `StopPageActionPresenter.presentWrappedInNavigation` installs
            // dismisses the same way.
            dismiss(animated: true)
        }
    }

    private func makeActions() -> TripPageActions {
        var actions = TripPageActions()

        actions.canSchedule = application.currentRegion?.supportsScheduleForRoute ?? true
        actions.canAlarm = departure.map(canCreateAlarm) ?? false
        // A Live Activity reports a countdown to a stop. Without a departure
        // there is no stop and nothing to count down to.
        actions.canStartLiveActivity = departure != nil && ActivityAuthorizationInfo().areActivitiesEnabled
        actions.canReportGhostBus = application.features.obaco == .running

        actions.onBack = { [weak self] in self?.goBack() }
        actions.onSelectStop = { [weak self] stopID in
            guard let self else { return }
            application.viewRouter.navigateTo(stopID: stopID, from: self)
        }
        actions.onBookmark = { [weak self] in self?.showBookmarkEditor() }
        actions.onSchedule = { [weak self] in self?.showSchedule() }
        actions.onAlarm = { [weak self] in self?.showAlarmPicker() }
        actions.onLiveActivity = { [weak self] in self?.startLiveActivity() }
        actions.onReportGhostBus = { [weak self] in self?.showGhostBusReport() }

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

    /// Building the draft: prefer `ArrivalDeparture` fields (stop-level context) when a departure
    /// is loaded, falling back to trip-level data from `TripConvertible` otherwise.
    private func showGhostBusReport() {
        let convertible = viewModel.tripConvertible
        let trip = convertible.trip

        var draft: GhostBusReportDraft
        if let departure {
            draft = GhostBusReportDraft(tripID: departure.tripID, serviceDate: departure.serviceDate)
            draft.stopID = departure.stopID
            draft.routeID = departure.routeID
            draft.vehicleID = departure.vehicleID
            draft.stopSequence = departure.stopSequence
            draft.predicted = departure.predicted
            draft.scheduledArrivalAt = departure.scheduledDate
            draft.predictedArrivalAt = departure.predicted ? departure.arrivalDepartureDate : nil
            draft.scheduleDeviationMinutes = departure.deviationFromScheduleInMinutes
            draft.predictionLastUpdatedAt = departure.lastUpdated
        } else {
            // TripConvertible's initializers guarantee exactly one of arrivalDeparture,
            // vehicleStatus, or tripDetails is set, so `serviceDate` always has a
            // non-departure source to resolve from here. Without a departure there is
            // no stop-level context.
            draft = GhostBusReportDraft(tripID: trip.id, serviceDate: convertible.serviceDate)
            draft.routeID = trip.routeID
            draft.vehicleID = convertible.vehicleID
        }

        let context = GhostBusReportContext(
            routeAndHeadsign: [departure?.routeShortName ?? trip.route?.shortName, departure?.tripHeadsign ?? trip.headsign]
                .compactMap { $0 }
                .joined(separator: " — "),
            stopName: departure?.stop.name,
            scheduledTime: draft.scheduledArrivalAt,
            vehicleID: draft.vehicleID
        )

        let shareLocationKey = "GhostBusReport.shareLocation"
        application.userDefaults.register(defaults: [shareLocationKey: true])

        let host = UIHostingController(rootView: GhostBusReportView(
            context: context,
            defaultShareLocation: application.userDefaults.bool(forKey: shareLocationKey),
            submit: { [weak self] waitDurationMinutes, comment, shareLocation in
                // `submit` is `async throws`, and `GhostBusReportView.performSubmit` reads a
                // plain return as success and dismisses the sheet. A guard failure has to
                // throw, not return, or the rider is told their report went out when it
                // never did. (Today `obacoService` is never nil once set — a region switch
                // replaces it or leaves the old one — so this guard is defense against
                // `self` deallocating and against that invariant changing, not a live path.)
                guard let self, let obacoService = self.application.obacoService else {
                    throw GhostBusReportSubmissionError.serviceUnavailable
                }
                self.application.userDefaults.set(shareLocation, forKey: shareLocationKey)

                var submitted = draft
                submitted.waitDurationMinutes = waitDurationMinutes
                submitted.comment = comment
                if shareLocation, let location = self.application.locationService.currentLocation {
                    submitted.userLatitude = location.coordinate.latitude
                    submitted.userLongitude = location.coordinate.longitude
                }

                _ = try await obacoService.postGhostBusReport(submitted, userID: self.application.userUUID)
            },
            onDismiss: { [weak self] in self?.presentedViewController?.dismiss(animated: true) }
        ))

        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(host, animated: true)
    }

    /// Why a ghost bus report couldn't be submitted before ever reaching the network.
    /// Surfaced through `GhostBusReportView`'s error alert, same as a network failure —
    /// see the `submit` closure in `showGhostBusReport()`.
    enum GhostBusReportSubmissionError: LocalizedError {
        /// The submit closure couldn't reach an Obaco service — the presenting
        /// controller deallocated, or `obacoService` was unexpectedly absent.
        case serviceUnavailable

        var errorDescription: String? {
            OBALoc(
                "trip_page.ghost_bus_report_unavailable",
                value: "This report couldn't be submitted because the reporting service isn't available right now. Please try again later.",
                comment: "Error shown when a ghost bus report can't be submitted because the region's Obaco service is unreachable."
            )
        }
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
            let activity = try Activity<TripAttributes>.requestProminent(
                attributes: TripAttributes(staticData: staticData),
                state: contentState
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
