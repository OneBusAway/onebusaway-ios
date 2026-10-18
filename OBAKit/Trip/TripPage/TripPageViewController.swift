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

/// Hosts `TripPageRootView` and owns every reach into `Application` the page needs —
/// navigation, alarms, bookmarks, schedules, Live Activities.
///
/// The root is `TripPageRootView`, a thin wrapper that applies
/// `.defaultAppStorage(application.userDefaults)` so the page's `@AppStorage`
/// shares the app-group suite with Settings — without it, compact mode and
/// reduced colors on the trip page read `UserDefaults.standard` and stay off.
///
/// Deliberately map-free. `TripViewController`, which this replaces, owned a
/// full-screen `MKMapView` and added its own floating panel as a child; pushed
/// into the stop sheet that nests a panel inside a panel. Keeping the map out of
/// here is what lets the same page be pushed into a sheet over the map tab's map
/// and, later, into a standalone host that supplies its own.
final class TripPageViewController: UIHostingController<TripPageRootView>,
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
        super.init(rootView: TripPageRootView(
            viewModel: viewModel,
            userDefaults: application.userDefaults,
            formatters: application.formatters,
            originTitle: originTitle,
            actions: TripPageActions()
        ))

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

        // Hidden here as well as in `viewWillAppear`, so the bar is already gone
        // on the first layout pass.
        hideNavigationBar(animated: false)

        registerForVerticalBarChanges { [weak self] in
            guard let self else { return }
            // Render even while covered: `viewWillAppear` puts the bar back to
            // match `showsSystemNavigationBar` on the way back, and a stale back
            // row would leave the page with two back controls, or none.
            render()
            guard navigationController?.topViewController === self else { return }
            hideNavigationBar(animated: true)
        }

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

        viewModel.$isLoading
            .sink { [weak self] isLoading in self?.refreshBarButton.isEnabled = !isLoading }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Again on every appearance, not just the first: leaving for a page
        // pushed on top gave that page the bar back. Animated with the pop, so
        // the bar doesn't vanish from the page above at the start of a back swipe.
        hideNavigationBar(animated: animated)
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

        restoreNavigationBar(animated: animated)
    }

    // MARK: - Navigation bar

    /// The back row's refresh button, for when the system bar replaces the row.
    private lazy var refreshBarButton: UIBarButtonItem = {
        let item = UIBarButtonItem(image: UIImage(systemName: AppSymbol.refresh), primaryAction: UIAction { [weak self] _ in
            self?.viewModel.refresh()
        })
        item.accessibilityLabel = Strings.refresh
        return item
    }()

    /// Internal for tests: stands in for `traitCollection.presentsBarsVertically`,
    /// a system trait a test can't set.
    var presentsBarsVerticallyOverride: Bool?

    /// Whether the bar was hidden before this page hid it, so it can be put back
    /// the way it was. `nil` while the page isn't hiding it.
    private var navigationBarWasHidden: Bool?

    /// The page draws its own back row, so a navigation bar here would be a
    /// second one — and inside the sheet it would impose a top safe area that
    /// eats the sheet's scarce height.
    ///
    /// Only where nothing else decides the bar. The stop sheet's presenter, the
    /// stack's delegate, decides it on every push and pop, from
    /// `providesOwnSheetChrome`; a second owner would fight it.
    ///
    /// Except where `showsSystemNavigationBar`, which shows it instead.
    private func hideNavigationBar(animated: Bool) {
        guard let navigationController, navigationController.delegate == nil else { return }
        if navigationBarWasHidden == nil {
            navigationBarWasHidden = navigationController.isNavigationBarHidden
        }
        navigationController.setNavigationBarHidden(!showsSystemNavigationBar, animated: animated)
    }

    /// `true` when the system puts navigation bars in a vertical column beside the
    /// page (iPhone Duo) and the page was pushed onto an ordinary stack. There the
    /// bar costs the page no height, and its back button belongs in the column with
    /// the tabs — the page's own back row put a second back control, horizontally,
    /// at the top of the page. A sheet's stack has a delegate deciding the bar, and
    /// a modal root closes rather than goes back; both keep the row.
    private var showsSystemNavigationBar: Bool {
        guard presentsBarsVerticallyOverride ?? traitCollection.presentsBarsVertically, let navigationController, navigationController.delegate == nil else { return false }
        return backBehavior == .pop
    }

    /// Hands the bar back when navigation takes this page off screen (#1570):
    /// popped, it goes back the way the host had it; covered by a page pushed on
    /// top, it shows, since that page needs it for its back button, and the host's
    /// state waits for the pop. Not on a modal over the page or a tab switch,
    /// which leave it on top of its stack.
    ///
    /// Popped is read from the stack rather than `isMovingFromParent`, which a
    /// page covered by a push can report too.
    private func restoreNavigationBar(animated: Bool) {
        guard let wasHidden = navigationBarWasHidden, let navigationController else { return }
        if !navigationController.viewControllers.contains(self) {
            navigationBarWasHidden = nil
            navigationController.setNavigationBarHidden(wasHidden, animated: animated)
        } else if navigationController.topViewController !== self {
            navigationController.setNavigationBarHidden(false, animated: animated)
        }
    }

    // MARK: - Map focus

    /// What the map should be drawing while this page is up. The host decides
    /// which map that is — see `onMapFocusChanged`.
    let mapFocus = TripMapFocus()

    /// Set by whoever owns a map: called with the focus when this page appears
    /// and with `nil` when it leaves the stack.
    var onMapFocusChanged: ((TripMapFocus?) -> Void)?

    /// Set by a host that opens stops itself: the map panel, which shows a stop as a
    /// sheet of its own. `nil` pushes the stop through `ViewRouter`, which needs this
    /// page to be on a navigation stack.
    var onSelectStop: ((StopID) -> Void)?

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
        existingAlarm = lookUpAlarm()
        title = pageTitle
        navigationItem.rightBarButtonItem = showsSystemNavigationBar ? refreshBarButton : nil
        rootView = TripPageRootView(
            viewModel: viewModel,
            userDefaults: application.userDefaults,
            formatters: application.formatters,
            originTitle: originTitle,
            actions: makeActions(),
            backBehavior: backBehavior,
            showsBackRow: !showsSystemNavigationBar,
            hasAlarm: existingAlarm != nil,
            isTrackingLiveActivity: isTrackingLiveActivity,
            isCollapsed: isAtTip
        )
    }

    /// "Route 10 to Capitol Hill". The page hides its bar, so this mostly isn't
    /// drawn, but it names the page on the back button of anything pushed on top
    /// of it, which otherwise said only "Back", and in the iPhone Duo's side bar.
    private var pageTitle: String? {
        // `routeShortName` and `tripHeadsign` fall back to the route and trip
        // references, which trap until they've loaded; this runs from `init`.
        guard let departure, (departure.route as Route?) != nil, (departure.trip as Trip?) != nil else { return nil }
        let route = departure.routeShortName
        guard !route.isEmpty else { return nil }
        guard let headsign = departure.tripHeadsign, !headsign.isEmpty else { return route }
        return TripCardView.routeToHeadsign(route, headsign)
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

    /// Set by a host that has to end this page's presentation itself: the map panel's
    /// sheet, which stays up for as long as its route is on `SheetCoordinator`'s stack.
    /// Answers Back when there is nothing to pop to. `nil` falls back to UIKit's
    /// `dismiss`, which is right where UIKit did the presenting.
    var onClose: (() -> Void)?

    /// Back, resolved against the stack rather than assumed.
    ///
    /// The page is pushed from the Stop page and presented from the map sheet,
    /// and `popViewController` only works for the first — as the root of its own
    /// navigation controller it returns nil and leaves the rider pressing a
    /// button that does nothing.
    ///
    /// The map panel's sheet hosts the page with no stack at all, and closes it
    /// through `onClose`.
    private func goBack() {
        switch backBehavior {
        case .pop:
            navigationController?.popViewController(animated: true)
        case .dismiss:
            if let onClose {
                onClose()
                return
            }
            // UIKit forwards this up to whoever did the presenting, so it takes
            // the wrapping navigation controller with it. The Done button
            // `StopPageActionPresenter.presentWrappedInNavigation` installs
            // dismisses the same way.
            dismiss(animated: true)
        }
    }

    /// Constructs the actions available to the trip page based on available departure details and region capabilities.
    /// - Returns: Configured `TripPageActions` for user interactions on the trip sheet.
    private func makeActions() -> TripPageActions {
        var actions = TripPageActions()

        let stopID = departure?.stopID ?? viewModel.tripDetails?.stopTimes.first?.stopID
        actions.canSchedule = routeID != nil && ScheduleViewControllerFactory.canPresentSchedule(stopID: stopID, application: application)
        // An alarm already set can always be removed, even once it's too late to set one.
        actions.canAlarm = existingAlarm != nil || (departure.map(canCreateAlarm) ?? false)
        // A Live Activity reports a countdown to a stop. Without a departure
        // there is no stop and nothing to count down to.
        actions.canStartLiveActivity = departure != nil && ActivityAuthorizationInfo().areActivitiesEnabled
        actions.canReportGhostBus = application.features.obaco == .running

        actions.onBack = { [weak self] in self?.goBack() }
        actions.onSelectStop = { [weak self] stopID in
            guard let self else { return }
            if let onSelectStop {
                onSelectStop(stopID)
                return
            }
            application.viewRouter.navigateTo(stopID: stopID, from: self)
        }
        actions.onBookmark = { [weak self] in self?.showBookmarkEditor() }
        actions.onSchedule = { [weak self] in self?.showSchedule() }
        actions.onAlarm = { [weak self] in
            guard let self else { return }
            if let existingAlarm = self.existingAlarm {
                removeAlarm(existingAlarm)
            } else {
                showAlarmPicker()
            }
        }
        actions.onLiveActivity = { [weak self] in self?.startLiveActivity() }
        actions.onReportGhostBus = { [weak self] in self?.showGhostBusReport() }

        return actions
    }

    /// Resolves the route identifier from available departure or trip information.
    private var routeID: RouteID? {
        if let departure {
            return departure.routeID
        }
        if let trip = viewModel.tripDetails?.trip {
            return trip.routeID
        }
        if let trip = viewModel.tripConvertible.tripDetails?.trip {
            return trip.routeID
        }
        if let trip = viewModel.tripConvertible.vehicleStatus?.trip {
            return trip.routeID
        }
        if let arrivalDeparture = viewModel.tripConvertible.arrivalDeparture {
            return arrivalDeparture.routeID
        }
        return nil
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

    /// Presents the schedule for the trip's route, or falls back to the stop schedule
    /// when the region lacks route schedule support and a stop identifier is available.
    private func showSchedule() {
        let stopID = departure?.stopID ?? viewModel.tripDetails?.stopTimes.first?.stopID
        guard let routeID,
              let scheduleVC = ScheduleViewControllerFactory.makeScheduleViewController(
                  routeID: routeID,
                  stopID: stopID,
                  application: application
              )
        else { return }
        present(scheduleVC, animated: true)
    }

    /// Building the draft: prefer `ArrivalDeparture` fields (stop-level context) when a departure
    /// is loaded, falling back to trip-level data from `TripConvertible` otherwise.
    private func makeGhostBusReportDraft() -> GhostBusReportDraft {
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
        return draft
    }

    private func showGhostBusReport() {
        let trip = viewModel.tripConvertible.trip
        let draft = makeGhostBusReportDraft()

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

    /// The alarm the rider set on this departure, from this page or the stop page.
    /// The button said "Add alarm" whether or not there was one, so pressing it
    /// again armed a second alarm, and the first couldn't be removed from here.
    ///
    /// Looked up once per `render()`: reading `alarms` decodes the whole store.
    private var existingAlarm: Alarm?

    private var isRemovingAlarm = false

    private func lookUpAlarm() -> Alarm? {
        guard let departure, let regionID = application.currentRegion?.regionIdentifier else { return nil }
        let store = application.userDataStore
        guard !store.alarms.isEmpty else { return nil }
        // As the stop page does: an expired alarm has fired, so it's nothing to remove.
        store.deleteExpiredAlarms()
        return AlarmVisitIdentity.alarm(for: departure, regionID: regionID, in: store.alarms)
    }

    /// Mirrors `StopViewModel.cancelAlarm(for:)`: the server copy goes first, so
    /// a failure leaves the rider an alarm they can still see and cancel.
    private func removeAlarm(_ alarm: Alarm) {
        // A second activation while the delete is in flight would delete and
        // announce twice.
        guard !isRemovingAlarm else { return }
        isRemovingAlarm = true
        Task { @MainActor in
            defer { isRemovingAlarm = false }
            do {
                guard let obacoService = application.obacoService else {
                    throw StopViewModel.AlarmCancellationError.serviceUnavailable
                }
                try await obacoService.deleteAlarm(url: alarm.url)
            } catch APIError.requestNotFound {
                // It already fired, and the server deleted it.
            } catch {
                await AlertPresenter.show(error: error, presentingController: self)
                return
            }
            application.userDataStore.delete(alarm: alarm)
            render()
            AccessibilityNotification.Announcement(AlarmVisitIdentity.removedAnnouncement).post()
        }
    }

    // MARK: - AlarmBuilderDelegate

    func alarmBuilderStartedRequest(_ alarmBuilder: AlarmBuilder) {
        ProgressHUD.show()
    }

    func alarmBuilder(_ alarmBuilder: AlarmBuilder, alarmCreated alarm: Alarm) {
        // `AlarmBuilder` doesn't persist what it creates. Without this the page
        // can't find the alarm it just set, so the button kept saying "Add alarm".
        application.userDataStore.add(alarm: alarm)

        if alarmBuilder.trackOnLockScreen {
            startLiveActivity()
        }

        let message = OBALoc("stop_controller.alarm_created_message", value: "Alarm created", comment: "A message that appears when a user's alarm is created.")
        ProgressHUD.showSuccessAndDismiss(message: message)
        render()
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
            regionID: application.currentRegion?.regionIdentifier ?? 0,
            tripID: departure.tripID
        )

        // Shares the mapping with the bookmark and stop paths rather than
        // hand-rolling a third copy (#1393). Still one arrival: this screen holds
        // a single `departure` and no stop arrival list, so there is no second one
        // to offer — what changes is that a future edit to the mapping reaches
        // here too.
        let contentState = BookmarkActions.contentState(from: [departure])

        // The same trip can be started from here, the stop page, and the
        // bookmarks list. Without this guard one stop ends up with two Lock
        // Screen cards and two OBACloud push registrations. Re-Track still has to
        // promote, as the other two paths do: after tracking A then B the Island
        // is on B with A demoted to `demotedScore`, so tapping Track on A again
        // must bump A back rather than only re-rendering this screen.
        if let existing = Activity<TripAttributes>.running(matching: staticData) {
            Logger.info("Live Activity already running for stop \(staticData.stopID) route \(staticData.routeShortName); promoting instead of duplicating.")
            let existingID = existing.id
            Task {
                await Activity<TripAttributes>.promoteToDynamicIsland(
                    activityID: existingID,
                    state: contentState
                )
            }
            isTrackingLiveActivity = true
            render()
            return
        }

        do {
            let activity = try Activity<TripAttributes>.requestProminent(
                staticData: staticData,
                state: contentState,
                userDefaults: application.userDefaults
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
