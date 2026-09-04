//
//  StopPageActionPresenter.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import SwiftUI
import ActivityKit
import CoreLocation
import OBAKitCore

/// Every flow that leaves the Stop page or presents a modal over it.
///
/// Extracted from `StopPageViewController` so both the pushed presentation and
/// the SwiftUI map sheet drive the same code. The sheet has no view controller
/// of its own, so the presenting controller arrives as a provider closure
/// resolved at call time rather than a stored reference — see
/// `AppSheetViewFactory`, which walks to the topmost presented controller so
/// modals land above the sheet stack instead of underneath it.
@MainActor
/// `ObservableObject` carries no published state — it is what lets
/// `StopDetailsSheetView` hold this in a `@StateObject`, whose `wrappedValue`
/// is an autoclosure and so only ever built once. `@State(wrappedValue:)` takes
/// a plain value, so the parent's every body pass allocated a presenter (and
/// every modal's weak reference to it) only to discard it.
final class StopPageActionPresenter: NSObject, ObservableObject {

    /// Not `private`: `AppSheetViewFactoryTests` asserts the factory forwards
    /// its own `Application` here rather than building a second one, the same
    /// handoff it checks on `MoreSheetHost`.
    let application: Application
    private let presentingController: () -> UIViewController?

    init(application: Application, presentingController: @escaping () -> UIViewController?) {
        self.application = application
        self.presentingController = presentingController
        super.init()
    }

    /// Resolves the controller to present from, logging when it cannot.
    ///
    /// Every flow here is gated on this, so an unresolvable controller turns the
    /// whole Stop page into dead buttons: Schedule, Bookmark, Filter, Report a
    /// Problem, walking directions, alarms, surveys and donations all return
    /// early with nothing on screen. Left silent, that is indistinguishable from
    /// a UI bug. `TripPresentationBridge.present` logs the same condition, so
    /// the two halves of the sheet system report failures the same way.
    ///
    /// - Parameter action: what was being attempted, for the log line.
    private func presentationHost(for action: String) -> UIViewController? {
        guard let controller = presentingController() else {
            Logger.error("StopPageActionPresenter: dropping \(action) — no presenting controller resolved.")
            return nil
        }
        return controller
    }

    /// Memoized answer to "is Google Maps installed?".
    ///
    /// `application.canOpenURL` is an XPC round-trip and Google Maps can't be
    /// installed or removed within a screen's lifetime, so resolve it once. The
    /// coordinate is a parameter rather than stored state: as a `lazy var` reading
    /// a property that only one caller happened to set first, the answer would
    /// cache as `false` forever if anything ever asked before that caller ran.
    private var cachedGoogleMapsAvailable: Bool?

    func googleMapsAvailable(coordinate: CLLocationCoordinate2D) -> Bool {
        if let cachedGoogleMapsAvailable { return cachedGoogleMapsAvailable }

        guard let url = AppInterop.googleMapsWalkingDirectionsURL(coordinate: coordinate) else {
            // No URL for this coordinate says nothing about whether the app is
            // installed, so don't memoize it.
            return false
        }

        let available = application.canOpenURL(url)
        cachedGoogleMapsAvailable = available
        return available
    }

    /// Set by a host that owns a map, so a trip opened from the Stop page can
    /// point that map at the trip. Left nil where the page was pushed
    /// full-screen — there is no map behind it to focus.
    var onTripPagePush: ((TripPageViewController) -> Void)?

    // MARK: - Navigation Handler

    /// Builds the handler the SwiftUI layer consumes. `closeSheet` is a no-op
    /// for the pushed presentation, which leaves via the navigation bar.
    ///
    /// Assembled from three grouped factories below rather than as one literal,
    /// which keeps each body short enough to read (and inside
    /// `function_body_length`).
    func makeNavigationHandler(
        viewModel: StopViewModel,
        closeSheet: @escaping () -> Void = {}
    ) -> StopPageNavigationHandler {
        let trip = makeTripClosures(viewModel: viewModel)
        let alarms = makeAlarmClosures(viewModel: viewModel)
        let stop = makeStopClosures(viewModel: viewModel)

        return StopPageNavigationHandler(
            showTrip: trip.showTrip,
            showScheduleForStop: trip.showScheduleForStop,
            showScheduleForRoute: trip.showScheduleForRoute,
            canScheduleForRoute: application.currentRegion?.supportsScheduleForRoute ?? true,
            showWalkingDirections: stop.showWalkingDirections,
            showAlertDetail: stop.showAlertDetail,
            showBookmarkEditor: stop.showBookmarkEditor,
            shareTrip: trip.shareTrip,
            showAlarmPicker: alarms.showAlarmPicker,
            startLiveActivity: alarms.startLiveActivity,
            showExternalSurveyError: { [weak self] in self?.showExternalSurveyError() },
            showDonation: { [weak self] in self?.showDonation() },
            dismissDonation: { [weak self] onHide in self?.showDonationDismiss(onHide: onHide) },
            makeTripPreview: trip.makeTripPreview,
            showRouteFilter: stop.showRouteFilter,
            showServiceAlerts: stop.showServiceAlerts,
            showNearbyStops: stop.showNearbyStops,
            showReportProblem: stop.showReportProblem,
            closeSheet: closeSheet
        )
    }

    // MARK: - Navigation Handler Factories

    /// Everything scoped to one departure's trip.
    private struct TripClosures {
        let showTrip: (ArrivalDeparture) -> Void
        let showScheduleForStop: () -> Void
        let showScheduleForRoute: (ArrivalDeparture) -> Void
        let shareTrip: (ArrivalDeparture) -> Void
        let makeTripPreview: (ArrivalDeparture) -> AnyView
    }

    private func makeTripClosures(viewModel: StopViewModel) -> TripClosures {
        TripClosures(
            showTrip: { [weak self] departure in
                self?.showTripPage(for: departure, originTitle: viewModel.stop?.name)
            },
            showScheduleForStop: { [weak self] in
                self?.showScheduleForStop(stopID: viewModel.stopID)
            },
            showScheduleForRoute: { [weak self] departure in
                self?.showScheduleForRoute(departure)
            },
            shareTrip: { [weak self] departure in
                self?.shareTrip(departure)
            },
            makeTripPreview: { [weak self] departure in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(
                    TripViewControllerPreview(departure: departure, application: self.application)
                        .frame(width: 320, height: 400)
                )
            }
        )
    }

    /// The two alarm affordances, which both need the view model itself rather
    /// than a value read off it.
    private struct AlarmClosures {
        let showAlarmPicker: (ArrivalDeparture) -> Void
        let startLiveActivity: (ArrivalDeparture) -> Void
    }

    private func makeAlarmClosures(viewModel: StopViewModel) -> AlarmClosures {
        AlarmClosures(
            showAlarmPicker: { [weak self] departure in
                self?.showAlarmPicker(for: departure, viewModel: viewModel)
            },
            startLiveActivity: { [weak self] departure in
                self?.startLiveActivity(for: departure, viewModel: viewModel)
            }
        )
    }

    /// Everything scoped to the stop as a whole.
    private struct StopClosures {
        let showWalkingDirections: () -> Void
        let showAlertDetail: (ServiceAlert) -> Void
        let showBookmarkEditor: (ArrivalDeparture?) -> Void
        let showRouteFilter: () -> Void
        let showServiceAlerts: () -> Void
        let showNearbyStops: () -> Void
        let showReportProblem: () -> Void
    }

    private func makeStopClosures(viewModel: StopViewModel) -> StopClosures {
        StopClosures(
            showWalkingDirections: { [weak self] in
                guard let coordinate = viewModel.stop?.coordinate else { return }
                self?.showWalkingDirections(coordinate: coordinate)
            },
            showAlertDetail: { [weak self] alert in
                guard let self, let host = self.presentationHost(for: "alert detail") else { return }
                self.application.viewRouter.navigateTo(alert: alert, from: host)
            },
            showBookmarkEditor: { [weak self] departure in
                self?.showBookmarkEditor(
                    for: departure,
                    stop: viewModel.stop,
                    preloadedArrivals: viewModel.stopArrivals?.arrivalsAndDepartures
                )
            },
            showRouteFilter: { [weak self] in
                guard let self, let stop = viewModel.stop else { return }
                self.showRouteFilter(
                    stop: stop,
                    hiddenRoutes: Set(viewModel.stopPreferences.hiddenRoutes),
                    onUpdate: { prefs in viewModel.updateStopPreferences(prefs) }
                )
            },
            showServiceAlerts: { [weak self] in
                self?.showServiceAlerts(viewModel.stopArrivals?.serviceAlerts ?? [])
            },
            showNearbyStops: { [weak self] in
                guard let coordinate = viewModel.stop?.coordinate else { return }
                self?.showNearbyStops(coordinate: coordinate)
            },
            showReportProblem: { [weak self] in
                guard let stop = viewModel.stop else { return }
                self?.showReportProblem(stop: stop)
            }
        )
    }

    // MARK: - Trip

    /// Opens the SwiftUI trip page — the row context menu's "Show Trip Details"
    /// and the departure row's tap target.
    ///
    /// Both used to go through `ViewRouter.navigateTo(arrivalDeparture:from:)`,
    /// which still builds the old `TripViewController` for the surfaces that push
    /// full-screen with no map behind them. Routed here instead, so every way out
    /// of the Stop page reaches the same screen.
    func showTripPage(for arrivalDeparture: ArrivalDeparture, originTitle: String?) {
        guard let host = presentationHost(for: "trip") else { return }
        let tripPage = TripPageViewController(
            application: application,
            arrivalDeparture: arrivalDeparture,
            originTitle: originTitle
        )
        // Only a host that owns a map answers this. Where the page was pushed
        // full-screen there is nothing behind it to point anywhere.
        onTripPagePush?(tripPage)
        // `viewRouter.navigate(to:from:)` ends in a push, so it is only safe
        // where a navigation stack exists. The pushed page stays on that path;
        // the modal sheet, which has no stack of its own, gets a modal instead.
        if host.navigationController != nil {
            application.viewRouter.navigate(to: tripPage, from: host)
        } else {
            presentWrappedInNavigation(tripPage, from: host)
        }
    }

    /// Starts the destination-picker → share-sheet flow for a departure.
    func shareTrip(_ arrivalDeparture: ArrivalDeparture) {
        guard let host = presentationHost(for: "share trip") else { return }
        // Rebuilt per share rather than stored once: the coordinator binds to a
        // single presenting controller, and the sheet's topmost controller is
        // resolved fresh at every call. Retained until the next share so the
        // picker's delegate callbacks survive the flow; it holds its presenter
        // weakly, so this creates no cycle.
        let coordinator = TripSharingCoordinator(application: application, presenter: host)
        tripSharingCoordinator = coordinator
        coordinator.start(arrivalDeparture: arrivalDeparture)
    }

    private var tripSharingCoordinator: TripSharingCoordinator?

    // MARK: - Schedules

    func showScheduleForStop(stopID: StopID) {
        let controller = ScheduleForStopViewController(stopID: stopID, application: application)
        presentationHost(for: "schedule for stop")?.present(controller, animated: true)
    }

    func showScheduleForRoute(_ arrivalDeparture: ArrivalDeparture) {
        let controller = ScheduleForRouteViewController(routeID: arrivalDeparture.routeID, application: application)
        presentationHost(for: "schedule for route")?.present(controller, animated: true)
    }

    // MARK: - Bookmarks

    /// `nil` starts the stop-level "Add Bookmark" workflow; a departure jumps
    /// straight into editing a trip bookmark.
    func showBookmarkEditor(
        for arrivalDeparture: ArrivalDeparture?,
        stop: Stop?,
        preloadedArrivals: [ArrivalDeparture]?
    ) {
        guard let host = presentationHost(for: "bookmark editor") else { return }

        if let arrivalDeparture {
            let controller = EditBookmarkViewController(application: application, arrivalDeparture: arrivalDeparture, bookmark: nil, delegate: self)
            let navigation = UINavigationController(rootViewController: controller)
            application.viewRouter.present(navigation, from: host)
        } else {
            guard let stop else { return }
            let controller = AddBookmarkViewController(application: application, stop: stop, preloadedArrivals: preloadedArrivals, delegate: self)
            let navigation = application.viewRouter.buildNavigation(controller: controller)
            application.viewRouter.present(navigation, from: host, isModal: true)
        }
    }

    // MARK: - Route Filter

    func showRouteFilter(stop: Stop, hiddenRoutes: Set<RouteID>, onUpdate: @escaping (StopPreferences) -> Void) {
        stopPreferencesUpdate = onUpdate
        let view = StopPreferencesWrappedView(stop, initialHiddenRoutes: hiddenRoutes, delegate: self)
            .environment(\.coreApplication, application)
        presentationHost(for: "route filter")?.present(UIHostingController(rootView: view), animated: true)
    }

    private var stopPreferencesUpdate: ((StopPreferences) -> Void)?

    // MARK: - Location

    func showNearbyStops(coordinate: CLLocationCoordinate2D) {
        pushOrPresent(NearbyStopsViewController(coordinate: coordinate, application: application))
    }

    func showServiceAlerts(_ alerts: [ServiceAlert]) {
        pushOrPresent(ServiceAlertListController(application: application, serviceAlerts: alerts))
    }

    /// Pushes when the presenting controller sits in a navigation stack, and
    /// presents modally when it does not.
    ///
    /// The pushed Stop page is inside a `UINavigationController`, so it pushes as
    /// it always has. The map sheet's presenting controller is the SwiftUI
    /// hosting controller behind `.sheet(...)`, which has no navigation stack at
    /// all — and `ViewRouter.navigate(to:from:)` opens with
    /// `assert(fromController.navigationController != nil)`, so routing a sheet
    /// flow through it traps in debug and silently does nothing in release.
    private func pushOrPresent(_ controller: UIViewController) {
        guard let host = presentationHost(for: "\(type(of: controller))") else { return }

        if host.navigationController != nil {
            application.viewRouter.navigate(to: controller, from: host)
            return
        }

        presentWrappedInNavigation(controller, from: host)
    }

    /// Wraps a would-be-pushed controller for modal presentation, giving it the
    /// Done button it would otherwise lack — pushed controllers rely on the
    /// navigation stack's back button, which a modal has no equivalent of.
    private func presentWrappedInNavigation(_ controller: UIViewController, from host: UIViewController) {
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak controller] _ in
                controller?.dismiss(animated: true)
            }
        )
        let navigation = application.viewRouter.buildNavigation(controller: controller)
        application.viewRouter.present(navigation, from: host, isModal: true)
    }

    func showReportProblem(stop: Stop) {
        guard let host = presentationHost(for: "report a problem") else { return }
        let controller = ReportProblemViewController(application: application, stop: stop)
        let navigation = application.viewRouter.buildNavigation(controller: controller)
        application.viewRouter.present(navigation, from: host, isModal: true)
    }

    /// One available maps app opens directly; more than one presents an action
    /// sheet to disambiguate.
    func showWalkingDirections(coordinate: CLLocationCoordinate2D) {
        var options: [(title: String, url: URL)] = []

        if let appleMapsURL = AppInterop.appleMapsWalkingDirectionsURL(coordinate: coordinate) {
            options.append((
                OBALoc("stops_controller.walking_directions_apple", value: "Walking Directions (Apple Maps)", comment: "Button that launches Apple's maps.app with walking directions to this stop"),
                appleMapsURL
            ))
        }

        #if !targetEnvironment(simulator)
        if let googleMapsURL = AppInterop.googleMapsWalkingDirectionsURL(coordinate: coordinate),
           googleMapsAvailable(coordinate: coordinate) {
            options.append((
                OBALoc("stops_controller.walking_directions_google", value: "Walking Directions (Google Maps)", comment: "Button that launches Google Maps with walking directions to this stop"),
                googleMapsURL
            ))
        }
        #endif

        guard let first = options.first else { return }

        if options.count == 1 {
            application.open(first.url, options: [:], completionHandler: nil)
            return
        }

        let sheet = UIAlertController(
            title: OBALoc("stops_controller.walking_directions", value: "Walking Directions", comment: "Button that launches a maps app with walking directions to this stop"),
            message: nil,
            preferredStyle: .actionSheet
        )
        for option in options {
            sheet.addAction(UIAlertAction(title: option.title, style: .default) { [weak self] _ in
                self?.application.open(option.url, options: [:], completionHandler: nil)
            })
        }
        sheet.addAction(UIAlertAction(title: Strings.cancel, style: .cancel))
        present(actionSheet: sheet)
    }

    /// An unanchored action sheet is a hard crash on a regular-width device.
    /// The sheet presentation is iPhone-only, but the pushed presentation is
    /// not, and both come through here.
    private func present(actionSheet: UIAlertController) {
        guard let host = presentationHost(for: "action sheet") else { return }
        if let popover = actionSheet.popoverPresentationController {
            popover.sourceView = host.view
            popover.sourceRect = CGRect(origin: host.view.center, size: .zero)
        }
        host.present(actionSheet, animated: true)
    }

    // MARK: - Surveys

    func showFullSurvey(_ survey: Survey, heroResponseID: String?, stop: Stop?, stopID: StopID) {
        let controller = SurveyViewController(
            survey: survey,
            surveyService: application.surveyService,
            stop: stop,
            stopID: stopID,
            stopLocation: stop?.coordinate,
            heroResponseID: heroResponseID
        )
        presentationHost(for: "full survey")?.present(UINavigationController(rootViewController: controller), animated: true)
    }

    func showExternalSurveyError() {
        let alert = UIAlertController(
            title: OBALoc("stop_controller.external_survey_error.title", value: "Can't Open Survey", comment: "Title shown when an external survey link cannot be opened"),
            message: OBALoc("stop_controller.external_survey_error.message", value: "This survey link couldn't be opened. Please try again later.", comment: "Message shown when an external survey link cannot be opened"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Strings.ok, style: .default))
        presentationHost(for: "external survey error")?.present(alert, animated: true)
    }

    // MARK: - Donations

    func showDonation() {
        guard
            application.donationsManager.donationsEnabled,
            let donationModel = application.donationsManager.buildObservableDonationModel()
        else { return }

        let view = DonationLearnMoreView()
            .environmentObject(donationModel)
            .environmentObject(AnalyticsModel(application.analytics))

        // Not a bare `present`: `presentDonationModal` charges
        // `PromptCoordinator` for the session's one interruption *in the
        // presentation completion*, which is the whole reason it exists. Skipping
        // it would let a rider shown this modal still get the App Store review
        // prompt in the same session.
        presentationHost(for: "donation")?.presentDonationModal(view, coordinator: application.promptCoordinator)
    }

    /// `onHide` fires only when the user actually hides the card (dismiss or
    /// remind-later), so the SwiftUI page can drop the section immediately.
    func showDonationDismiss(onHide: @escaping () -> Void) {
        let controller = UIAlertController(
            title: Strings.donationsDismissAlertTitle,
            message: Strings.donationsDismissAlertMessage,
            preferredStyle: .actionSheet
        )

        controller.addAction(title: Strings.donationsDismissAlertButtonDismiss, style: .destructive) { [weak self] _ in
            self?.application.donationsManager.dismissDonationsRequests()
            onHide()
        }
        controller.addAction(title: Strings.donationsDismissAlertButtonRemindLater, style: .default) { [weak self] _ in
            self?.application.donationsManager.remindUserLater()
            onHide()
        }
        controller.addAction(title: Strings.cancel, style: .cancel, handler: nil)

        present(actionSheet: controller)
    }

    // MARK: - Alarms

    /// The in-flight alarm flow: the builder driving the bulletin, the departure
    /// it was opened for, and the view model to record the result on. Set
    /// together in `showAlarmPicker` and cleared together when the flow ends, so
    /// a finished flow stops holding the bulletin manager and its
    /// `ArrivalDeparture` alive for the rest of the presenter's life.
    private struct AlarmFlow {
        let builder: AlarmBuilder
        let departure: ArrivalDeparture
        weak var viewModel: StopViewModel?
    }

    private var alarmFlow: AlarmFlow?

    func showAlarmPicker(for arrivalDeparture: ArrivalDeparture, viewModel: StopViewModel) {
        // The SwiftUI alarm affordances are gated on `canCreateAlarm`, but that
        // gate is only re-evaluated on the refresh tick — a departure can slip
        // inside the one-minute floor while the row still offers the button.
        guard viewModel.canCreateAlarm(for: arrivalDeparture),
              let host = presentationHost(for: "alarm picker")
        else { return }

        let existingAlarm = viewModel.alarm(for: arrivalDeparture)
        let builder = AlarmBuilder(
            arrivalDeparture: arrivalDeparture,
            application: application,
            initialMinutes: existingAlarm.map { viewModel.alarmLeadTimeMinutes($0) },
            delegate: self
        )
        alarmFlow = AlarmFlow(builder: builder, departure: arrivalDeparture, viewModel: viewModel)
        builder.showBulletin(above: host)
    }

    /// - Parameter onPresented: runs as soon as the alert is on its way up, not
    ///   when it is dismissed. Callers use it to clear the view-model flag that
    ///   triggered this, so a later already-denied attempt re-fires the binding;
    ///   waiting for dismissal would leave the flag latched and swallow the
    ///   second attempt.
    func showAlarmPermissionDeniedAlert(onPresented: @escaping () -> Void) {
        let alert = UIAlertController(
            title: OBALoc("stop_page.alarm_permission_denied.title", value: "Notifications Are Off", comment: "Title of the alert shown when the user tries to set a departure alarm but notifications are denied in Settings."),
            message: String(
                format: OBALoc("stop_page.alarm_permission_denied.message", value: "To get departure alarms, allow notifications for %@ in Settings.", comment: "Body of the alert shown when the user tries to set a departure alarm but notifications are denied in Settings. %@ is the app name."),
                Bundle.main.appName
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Strings.cancel, style: .cancel))
        alert.addAction(UIAlertAction(
            title: OBALoc("stop_page.alarm_permission_denied.open_settings", value: "Open Settings", comment: "Button that opens the system Settings app so the user can enable notifications."),
            style: .default
        ) { [weak self] _ in
            guard let self, let url = URL(string: UIApplication.openSettingsURLString) else { return }
            self.application.open(url, options: [:], completionHandler: nil)
        })
        presentationHost(for: "alarm permission alert")?.present(alert, animated: true)
        onPresented()
    }

    func showError(_ error: Error) {
        guard let host = presentationHost(for: "error alert") else { return }
        Task { @MainActor in
            await AlertPresenter.show(error: error, presentingController: host)
        }
    }

    // MARK: - Live Activity

    func startLiveActivity(for departure: ArrivalDeparture, viewModel: StopViewModel) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let staticData = TripAttributes.StaticData(
            routeShortName: departure.routeShortName,
            routeHeadsign: departure.tripHeadsign ?? "",
            stopID: departure.stopID,
            routeColorHex: departure.route.color?.toHex(),
            regionID: application.currentRegion?.regionIdentifier ?? 0
        )

        // The same trip can be started from here and from the bookmarks list, so
        // this guard has to live on both start paths — otherwise one stop ends up
        // with two Lock Screen cards and two OBACloud push registrations. Re-Track
        // still needs to promote the existing activity: after A→B the Island is
        // on B with A demoted to 0, so tapping Track on A again must bump A.
        if let existing = Activity<TripAttributes>.running(matching: staticData) {
            Logger.info("Live Activity already running for stop \(staticData.stopID) route \(staticData.routeShortName); promoting instead of duplicating.")
            let existingID = existing.id
            Task {
                await Activity<TripAttributes>.promoteToDynamicIsland(activityID: existingID)
            }
            // Re-show the confirmation rather than appearing to do nothing.
            viewModel.signalLiveActivityStarted()
            return
        }

        guard let contentState = buildLiveActivityContentState(for: departure, viewModel: viewModel) else {
            Logger.error("Failed to build content state for Live Activity")
            return
        }

        do {
            let activity = try Activity<TripAttributes>.requestProminent(
                attributes: TripAttributes(staticData: staticData),
                state: contentState
            )
            application.liveActivityTracker.track(activity: activity, metadata: .init(departure))
            Logger.info("Started Live Activity with ID: \(activity.id)")
            viewModel.signalLiveActivityStarted()
        } catch {
            Logger.error("Failed to start Live Activity: \(error)")
            presentationHost(for: "live activity error")?.showLiveActivityErrorAlert()
        }
    }

    private func buildLiveActivityContentState(for departure: ArrivalDeparture, viewModel: StopViewModel) -> TripAttributes.ContentState? {
        let allArrivals = viewModel.stopArrivals?.arrivalsAndDepartures ?? [departure]
        return BookmarkActions.buildContentState(from: allArrivals, matching: departure)
    }

    // MARK: - User Activity

    /// Publishes this stop's `NSUserActivity` for Handoff, Siri and Spotlight.
    func makeUserActivity(stop: Stop) -> NSUserActivity? {
        guard let region = application.regionsService.currentRegion,
              let builder = application.userActivityBuilder
        else { return nil }
        return builder.userActivity(for: stop, region: region)
    }

    // MARK: - Snapshot

    /// Bridges the callback-based `MapSnapshotter` into async/await for the
    /// SwiftUI header.
    func loadSnapshot(stop: Stop, size: CGSize, traitCollection: UITraitCollection) async -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let factory = application.stopIconFactory
        // The header design is always-dark (white identity text over a dark
        // scrim), so render in dark style regardless of the system appearance.
        let traits = traitCollection.modifyingTraits { $0.userInterfaceStyle = .dark }
        return await withCheckedContinuation { continuation in
            let snapshotter = MapSnapshotter(size: size, stopIconFactory: factory)
            snapshotter.snapshot(stop: stop, traitCollection: traits) { image in
                // `MapSnapshotter`'s internal `MKMapSnapshotter.start`
                // completion is `[weak self]`, so the wrapper must outlive the
                // async render or the completion early-returns and this
                // continuation never resumes — leaving the header blank.
                withExtendedLifetime(snapshotter) {
                    continuation.resume(returning: image)
                }
            }
        }
    }
}

// MARK: - AlarmBuilderDelegate

extension StopPageActionPresenter: AlarmBuilderDelegate {
    func alarmBuilder(_ alarmBuilder: AlarmBuilder, alarmCreated alarm: Alarm) {
        // `alarmFlow` is set as a unit in `showAlarmPicker`, so a builder
        // reporting success always has one — unless the view model has since
        // been released, in which case there is nothing left to record on.
        if let flow = alarmFlow, let viewModel = flow.viewModel {
            // `replaceAlarm` indexes the new alarm synchronously and no-ops the
            // delete when the departure had no prior alarm, so it serves both
            // the create and change flows.
            Task { await viewModel.replaceAlarm(with: alarm, for: flow.departure) }

            if alarmBuilder.trackOnLockScreen {
                // Deferred for the same reason the failure path below is.
                // `AlarmBuilder.createAlarm` calls this delegate method *before*
                // the `defer` that dismisses its bulletin, so the bulletin is
                // still the topmost controller and `presentationHost` resolves to
                // it. `startLiveActivity` presents an error alert when
                // `Activity.request` throws — activities disabled mid-flow, quota,
                // a push-token failure — and an alert raised on a controller that
                // is about to be dismissed either flashes away with it or collides
                // with its transition, leaving the bulletin's view on screen and
                // unresponsive.
                let departure = flow.departure
                Task { @MainActor in
                    await waitForBulletinDismissal(alarmBuilder)
                    startLiveActivity(for: departure, viewModel: viewModel)
                }
            }
        }

        let message = OBALoc("stop_controller.alarm_created_message", value: "Alarm created", comment: "A message that appears when a user's alarm is created.")
        ProgressHUD.showSuccessAndDismiss(message: message)
        alarmFlow = nil
    }

    func alarmBuilder(_ alarmBuilder: AlarmBuilder, error: Error) {
        ProgressHUD.dismiss()

        // Report only once the bulletin is gone.
        //
        // `AlarmBuilder.createAlarm` calls this delegate method *before* the
        // `defer` that dismisses its bulletin, and `showBulletin(above:)` is a
        // plain modal presentation — so right now the bulletin is the topmost
        // controller and `presentingController()` resolves to it. Presenting the
        // alert there puts two modal transitions in flight at once: the alert
        // appears on a controller that is about to be dismissed, goes away with
        // it, and the bulletin's view is left on screen and unresponsive.
        Task { @MainActor in
            await waitForBulletinDismissal(alarmBuilder)
            showError(error)
        }
        alarmFlow = nil
    }

    /// How long to wait for the alarm bulletin to finish dismissing before
    /// reporting anyway. Bounded so a bulletin that somehow lingers can never
    /// swallow the error entirely.
    private static let bulletinDismissalTimeout: Duration = .seconds(2)
    private static let bulletinDismissalPollInterval: Duration = .milliseconds(50)

    private func waitForBulletinDismissal(_ alarmBuilder: AlarmBuilder) async {
        let deadline = ContinuousClock.now + Self.bulletinDismissalTimeout
        while alarmBuilder.bulletinManager.isShowingBulletin, ContinuousClock.now < deadline {
            try? await Task.sleep(for: Self.bulletinDismissalPollInterval)
        }

        // Falling through on the deadline is deliberate — better a stacked alert
        // than a swallowed one — but the two outcomes are indistinguishable on
        // screen, and only this one leaves the rider looking at an error alert
        // over a bulletin that never went away.
        if alarmBuilder.bulletinManager.isShowingBulletin {
            Logger.error("StopPageActionPresenter: alarm bulletin still showing after \(Self.bulletinDismissalTimeout); reporting over it.")
        }
    }
}

// MARK: - BookmarkEditorDelegate

extension StopPageActionPresenter: BookmarkEditorDelegate {
    func bookmarkEditorCancelled(_ viewController: UIViewController) {
        viewController.dismiss(animated: true, completion: nil)
    }

    func bookmarkEditor(_ viewController: UIViewController, editedBookmark bookmark: Bookmark, isNewBookmark: Bool) {
        viewController.dismiss(animated: true) {
            let msg = isNewBookmark
                ? OBALoc("stops_controller.created_new_bookmark", value: "Added Bookmark", comment: "Message displayed when a new bookmark is created.")
                : OBALoc("stops_controller.updated_bookmark", value: "Updated Bookmark", comment: "Message displayed an existing bookmark is updated.")
            ProgressHUD.showSuccessAndDismiss(message: msg, dismissAfter: 1.0)
        }
    }
}

// MARK: - StopPreferencesViewDelegate

extension StopPageActionPresenter: StopPreferencesViewDelegate {
    func stopPreferences(stopID: StopID, updated stopPreferences: StopPreferences) {
        stopPreferencesUpdate?(stopPreferences)
    }
}
