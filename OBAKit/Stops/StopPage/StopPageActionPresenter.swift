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
final class StopPageActionPresenter: NSObject {

    private let application: Application
    private let presentingController: () -> UIViewController?

    init(application: Application, presentingController: @escaping () -> UIViewController?) {
        self.application = application
        self.presentingController = presentingController
        super.init()
    }

    /// `application.canOpenURL` is an XPC round-trip and Google Maps can't be
    /// installed or removed within a screen's lifetime, so resolve availability
    /// once instead of on every chrome rebuild.
    private lazy var googleMapsAvailable: Bool = {
        guard let coordinate = lastKnownCoordinate,
              let url = AppInterop.googleMapsWalkingDirectionsURL(coordinate: coordinate)
        else { return false }
        return application.canOpenURL(url)
    }()

    /// Set whenever a flow is invoked with a stop, so `googleMapsAvailable` has
    /// a coordinate to probe with.
    private var lastKnownCoordinate: CLLocationCoordinate2D?

    /// Set by a host that owns a map, so a trip opened from the Stop page can
    /// point that map at the trip. Left nil where the page was pushed
    /// full-screen — there is no map behind it to focus.
    var onTripPagePush: ((TripPageViewController) -> Void)?

    // MARK: - Navigation Handler

    /// Builds the handler the SwiftUI layer consumes. `closeSheet` is a no-op
    /// for the pushed presentation, which leaves via the navigation bar.
    func makeNavigationHandler(
        viewModel: StopViewModel,
        closeSheet: @escaping () -> Void = {}
    ) -> StopPageNavigationHandler {
        StopPageNavigationHandler(
            showTrip: { [weak self] departure in
                self?.showTripPage(for: departure, originTitle: viewModel.stop?.name)
            },
            showScheduleForStop: { [weak self] in
                self?.showScheduleForStop(stopID: viewModel.stopID)
            },
            showScheduleForRoute: { [weak self] departure in
                self?.showScheduleForRoute(departure)
            },
            canScheduleForRoute: application.currentRegion?.supportsScheduleForRoute ?? true,
            showWalkingDirections: { [weak self] in
                guard let coordinate = viewModel.stop?.coordinate else { return }
                self?.showWalkingDirections(coordinate: coordinate)
            },
            showAlertDetail: { [weak self] alert in
                guard let self, let host = self.presentingController() else { return }
                self.application.viewRouter.navigateTo(alert: alert, from: host)
            },
            showBookmarkEditor: { [weak self] departure in
                self?.showBookmarkEditor(
                    for: departure,
                    stop: viewModel.stop,
                    preloadedArrivals: viewModel.stopArrivals?.arrivalsAndDepartures
                )
            },
            showAlarmPicker: { [weak self] departure in
                self?.showAlarmPicker(for: departure, viewModel: viewModel)
            },
            startLiveActivity: { [weak self] departure in
                self?.startLiveActivity(for: departure, viewModel: viewModel)
            },
            showExternalSurveyError: { [weak self] in self?.showExternalSurveyError() },
            showDonation: { [weak self] in self?.showDonation() },
            dismissDonation: { [weak self] onHide in self?.showDonationDismiss(onHide: onHide) },
            makeTripPreview: { [weak self] departure in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(
                    TripViewControllerPreview(departure: departure, application: self.application)
                        .frame(width: 320, height: 400)
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
            },
            closeSheet: closeSheet
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
        guard let host = presentingController() else { return }
        let tripPage = TripPageViewController(
            application: application,
            arrivalDeparture: arrivalDeparture,
            originTitle: originTitle
        )
        // Only a host that owns a map answers this. Where the page was pushed
        // full-screen there is nothing behind it to point anywhere.
        onTripPagePush?(tripPage)
        application.viewRouter.navigate(to: tripPage, from: host)
    }

    // MARK: - Schedules

    func showScheduleForStop(stopID: StopID) {
        let controller = ScheduleForStopViewController(stopID: stopID, application: application)
        presentingController()?.present(controller, animated: true)
    }

    func showScheduleForRoute(_ arrivalDeparture: ArrivalDeparture) {
        let controller = ScheduleForRouteViewController(routeID: arrivalDeparture.routeID, application: application)
        presentingController()?.present(controller, animated: true)
    }

    // MARK: - Bookmarks

    /// `nil` starts the stop-level "Add Bookmark" workflow; a departure jumps
    /// straight into editing a trip bookmark.
    func showBookmarkEditor(
        for arrivalDeparture: ArrivalDeparture?,
        stop: Stop?,
        preloadedArrivals: [ArrivalDeparture]?
    ) {
        guard let host = presentingController() else { return }

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
        presentingController()?.present(UIHostingController(rootView: view), animated: true)
    }

    private var stopPreferencesUpdate: ((StopPreferences) -> Void)?

    // MARK: - Location

    func showNearbyStops(coordinate: CLLocationCoordinate2D) {
        guard let host = presentingController() else { return }
        let controller = NearbyStopsViewController(coordinate: coordinate, application: application)
        application.viewRouter.navigate(to: controller, from: host)
    }

    func showServiceAlerts(_ alerts: [ServiceAlert]) {
        guard let host = presentingController() else { return }
        let controller = ServiceAlertListController(application: application, serviceAlerts: alerts)
        application.viewRouter.navigate(to: controller, from: host)
    }

    func showReportProblem(stop: Stop) {
        guard let host = presentingController() else { return }
        let controller = ReportProblemViewController(application: application, stop: stop)
        let navigation = application.viewRouter.buildNavigation(controller: controller)
        application.viewRouter.present(navigation, from: host, isModal: true)
    }

    /// One available maps app opens directly; more than one presents an action
    /// sheet to disambiguate.
    func showWalkingDirections(coordinate: CLLocationCoordinate2D) {
        lastKnownCoordinate = coordinate

        var options: [(title: String, url: URL)] = []

        if let appleMapsURL = AppInterop.appleMapsWalkingDirectionsURL(coordinate: coordinate) {
            options.append((
                OBALoc("stops_controller.walking_directions_apple", value: "Walking Directions (Apple Maps)", comment: "Button that launches Apple's maps.app with walking directions to this stop"),
                appleMapsURL
            ))
        }

        #if !targetEnvironment(simulator)
        if let googleMapsURL = AppInterop.googleMapsWalkingDirectionsURL(coordinate: coordinate), googleMapsAvailable {
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
        guard let host = presentingController() else { return }
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
        presentingController()?.present(UINavigationController(rootViewController: controller), animated: true)
    }

    func showExternalSurveyError() {
        let alert = UIAlertController(
            title: OBALoc("stop_controller.external_survey_error.title", value: "Can't Open Survey", comment: "Title shown when an external survey link cannot be opened"),
            message: OBALoc("stop_controller.external_survey_error.message", value: "This survey link couldn't be opened. Please try again later.", comment: "Message shown when an external survey link cannot be opened"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Strings.ok, style: .default))
        presentingController()?.present(alert, animated: true)
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

        presentingController()?.present(UIHostingController(rootView: view), animated: true)
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

    private var alarmBuilder: AlarmBuilder?
    private var alarmBuilderDeparture: ArrivalDeparture?
    private weak var alarmViewModel: StopViewModel?

    func showAlarmPicker(for arrivalDeparture: ArrivalDeparture, viewModel: StopViewModel) {
        // The SwiftUI alarm affordances are gated on `canCreateAlarm`, but that
        // gate is only re-evaluated on the refresh tick — a departure can slip
        // inside the one-minute floor while the row still offers the button.
        guard viewModel.canCreateAlarm(for: arrivalDeparture),
              let host = presentingController()
        else { return }

        alarmBuilderDeparture = arrivalDeparture
        alarmViewModel = viewModel
        let existingAlarm = viewModel.alarm(for: arrivalDeparture)
        alarmBuilder = AlarmBuilder(
            arrivalDeparture: arrivalDeparture,
            application: application,
            initialMinutes: existingAlarm.map { viewModel.alarmLeadTimeMinutes($0) },
            delegate: self
        )
        alarmBuilder?.showBulletin(above: host)
    }

    func showAlarmPermissionDeniedAlert(onDismiss: @escaping () -> Void) {
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
        presentingController()?.present(alert, animated: true)
        onDismiss()
    }

    func showError(_ error: Error) {
        guard let host = presentingController() else { return }
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

        // Prominence so the Dynamic Island switches to this Track when another
        // trip is already live (#1189 Problem 2). Default score is 0 and equal
        // scores keep the first-started activity.
        let prominence = TripLiveActivityRelevance.prominenceScore()
        do {
            let activity = try Activity.request(
                attributes: TripAttributes(staticData: staticData),
                content: TripLiveActivityRelevance.content(
                    state: contentState,
                    staleDate: nil,
                    relevanceScore: prominence
                ),
                pushType: .token
            )
            application.liveActivityTracker.track(activity: activity, metadata: .init(departure))
            let activityID = activity.id
            Task {
                await Activity<TripAttributes>.demoteLivePeers(
                    exceptActivityID: activityID,
                    relativeTo: prominence
                )
            }
            Logger.info("Started Live Activity with ID: \(activity.id)")
            viewModel.signalLiveActivityStarted()
        } catch {
            Logger.error("Failed to start Live Activity: \(error)")
            presentingController()?.showLiveActivityErrorAlert()
        }
    }

    private func buildLiveActivityContentState(for departure: ArrivalDeparture, viewModel: StopViewModel) -> TripAttributes.ContentState? {
        let allArrivals = viewModel.stopArrivals?.arrivalsAndDepartures ?? [departure]
        let sameRoute = allArrivals.filter { $0.routeID == departure.routeID }
        let upcoming = sameRoute.isEmpty ? [departure] : Array(sameRoute.prefix(3))
        let arrivals = upcoming.map { arrDep in
            TripAttributes.ContentState.ArrivalInfo(
                departureTime: Int(arrDep.arrivalDepartureDate.timeIntervalSince1970),
                scheduleStatus: .init(arrDep.scheduleStatus),
                scheduleDeviation: arrDep.deviationFromScheduleInMinutes * 60,
                isArrival: arrDep.arrivalDepartureStatus == .arriving
            )
        }
        return TripAttributes.ContentState(arrivals: arrivals)
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
    func alarmBuilderStartedRequest(_ alarmBuilder: AlarmBuilder) {
        ProgressHUD.show()
    }

    func alarmBuilder(_ alarmBuilder: AlarmBuilder, alarmCreated alarm: Alarm) {
        if let departure = alarmBuilderDeparture, let viewModel = alarmViewModel {
            // `replaceAlarm` indexes the new alarm synchronously and no-ops the
            // delete when the departure had no prior alarm, so it serves both
            // the create and change flows.
            Task { await viewModel.replaceAlarm(with: alarm, for: departure) }

            if alarmBuilder.trackOnLockScreen {
                startLiveActivity(for: departure, viewModel: viewModel)
            }
        } else {
            alarmViewModel?.recordAlarmCreated(alarm)
        }

        let message = OBALoc("stop_controller.alarm_created_message", value: "Alarm created", comment: "A message that appears when a user's alarm is created.")
        ProgressHUD.showSuccessAndDismiss(message: message)
    }

    func alarmBuilder(_ alarmBuilder: AlarmBuilder, error: Error) {
        ProgressHUD.dismiss()
        showError(error)
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
