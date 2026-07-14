//
//  StopPageViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import SwiftUI
import Combine
import ActivityKit
import OBAKitCore

/// Hosting shell for the redesigned SwiftUI Stop page. Owns UIKit-side chrome
/// (nav bar items, menus) and keeps parity entry points (`Previewable`,
/// navigation-out modals) working while `FeatureFlags.useNewStopPageKey` is
/// enabled.
///
/// The root view is `StopPageRootView`, a thin wrapper that applies
/// `.defaultAppStorage(application.userDefaults)` so the page's `@AppStorage`
/// shares the app-group suite with the legacy screen. Everything that leaves the
/// page — trip/schedule/alert/bookmark navigation, the donation and survey
/// modals — is routed here through `StopPageNavigationHandler`, so the SwiftUI
/// layer stays router-free and holds no `Application` reference.
class StopPageViewController: UIHostingController<StopPageRootView>,
    AppContext,
    AlarmBuilderDelegate,
    BookmarkEditorDelegate,
    Idleable,
    StopPreferencesViewDelegate,
    Previewable {

    let application: Application
    let viewModel: StopViewModel
    private var cancellables = Set<AnyCancellable>()

    public var idleTimerFailsafe: Timer?

    private lazy var dataLoadFeedbackGenerator = DataLoadFeedbackGenerator(application: application)

    /// Gates the one-shot success haptic to the first arrivals load, matching
    /// `StopViewController.bindArrivalsSink()`; later refreshes are silent.
    private var firstLoad = true

    #if !targetEnvironment(simulator)
    /// `application.canOpenURL` is an XPC round-trip and Google Maps can't be
    /// installed or removed within a screen's lifetime, so resolve availability
    /// once instead of on every ~15s chrome rebuild. Evaluated lazily on the
    /// first `locationMenu()` build, by which point `viewModel.stop` is set.
    private lazy var googleMapsAvailable: Bool = {
        guard let coordinate = viewModel.stop?.coordinate,
              let url = AppInterop.googleMapsWalkingDirectionsURL(coordinate: coordinate)
        else { return false }
        return application.canOpenURL(url)
    }()
    #endif

    var bookmarkContext: Bookmark? {
        get { viewModel.bookmarkContext }
        set { viewModel.bookmarkContext = newValue }
    }

    var transferContext: TransferContext? {
        get { viewModel.transferContext }
        set { viewModel.transferContext = newValue }
    }

    convenience init(application: Application, stop: Stop) {
        self.init(application: application, stopID: stop.id, stop: stop)
    }

    convenience init(application: Application, stopID: StopID) {
        self.init(application: application, stopID: stopID, stop: nil)
    }

    private init(application: Application, stopID: StopID, stop: Stop?) {
        self.application = application
        self.viewModel = StopViewModel(application: application, stopID: stopID, stop: stop)

        // Seed with placeholder closures; `self` isn't available until super.init
        // returns, so the real handler (which captures `self`) is installed below.
        super.init(rootView: StopPageRootView(
            viewModel: viewModel,
            userDefaults: application.userDefaults,
            snapshotLoader: { _ in nil },
            navigation: Self.placeholderNavigation,
            formatters: application.formatters
        ))

        rootView = StopPageRootView(
            viewModel: viewModel,
            userDefaults: application.userDefaults,
            snapshotLoader: { [weak self] size in
                guard let self else { return nil }
                return await self.loadSnapshot(size: size)
            },
            navigation: makeNavigationHandler(),
            formatters: application.formatters
        )

        hidesBottomBarWhenPushed = false
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        configureBarButtons()
        bindChrome()
        bindArrivalsFeedback()
        bindSurveyPresentation()
        bindAlarmFeedback()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        disableIdleTimer()
        beginUserActivity()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        enableIdleTimer()
    }

    // MARK: - NSUserActivity

    /// Publishes this stop's `NSUserActivity` for Handoff, Siri and Spotlight.
    /// Ports `StopViewController.beginUserActivity()`; called on appearance and
    /// whenever the stop resolves.
    private func beginUserActivity() {
        guard let stop = viewModel.stop,
              let region = application.regionsService.currentRegion,
              let userActivityBuilder = application.userActivityBuilder
        else { return }

        self.userActivity = userActivityBuilder.userActivity(for: stop, region: region)
    }

    // MARK: - Navigation Handler

    /// A fully no-op handler used only to satisfy the required `rootView` before
    /// `self` is available; replaced immediately with `makeNavigationHandler()`.
    private static let placeholderNavigation = StopPageNavigationHandler(
        showTrip: { _ in },
        showScheduleForStop: {},
        showScheduleForRoute: { _ in },
        canScheduleForRoute: false,
        showWalkingDirections: {},
        showAlertDetail: { _ in },
        showBookmarkEditor: { _ in },
        showAlarmPicker: { _ in },
        startLiveActivity: { _ in },
        showExternalSurveyError: {},
        showDonation: {},
        dismissDonation: { _ in },
        makeTripPreview: { _ in AnyView(EmptyView()) }
    )

    private func makeNavigationHandler() -> StopPageNavigationHandler {
        StopPageNavigationHandler(
            showTrip: { [weak self] departure in
                guard let self else { return }
                self.application.viewRouter.navigateTo(arrivalDeparture: departure, from: self)
            },
            showScheduleForStop: { [weak self] in self?.showScheduleForStop() },
            showScheduleForRoute: { [weak self] departure in self?.showScheduleForRoute(for: departure) },
            canScheduleForRoute: application.currentRegion?.supportsScheduleForRoute ?? true,
            showWalkingDirections: { [weak self] in self?.showWalkingDirections() },
            showAlertDetail: { [weak self] alert in
                guard let self else { return }
                self.application.viewRouter.navigateTo(alert: alert, from: self)
            },
            showBookmarkEditor: { [weak self] departure in self?.showBookmarkEditor(for: departure) },
            showAlarmPicker: { [weak self] departure in self?.showAlarmPicker(for: departure) },
            startLiveActivity: { [weak self] departure in self?.startLiveActivity(for: departure) },
            showExternalSurveyError: { [weak self] in self?.showExternalSurveyError() },
            showDonation: { [weak self] in self?.showDonationUI() },
            dismissDonation: { [weak self] onHide in self?.showDonationDismissUI(onHide: onHide) },
            makeTripPreview: { [weak self] departure in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(
                    TripViewControllerPreview(departure: departure, application: self.application)
                        .frame(width: 320, height: 400)
                )
            }
        )
    }

    // MARK: - Combine Bindings

    /// Rebuilds the nav-bar chrome (right bar items) whenever the state the
    /// menus read changes. Mirrors `StopViewController.bindViewModel()`'s
    /// `configureTabBarButtons()` calls. No nav-bar title: the header card
    /// carries the stop identity.
    private func bindChrome() {
        viewModel.$stop
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.configureBarButtons()
                self?.beginUserActivity()
            }
            .store(in: &cancellables)

        viewModel.$stopPreferences
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.configureBarButtons() }
            .store(in: &cancellables)

        // The only chrome that reads `stopArrivals` is the File menu's service-alerts
        // action (enabled iff alerts exist). Collapse the ~15s refresh churn to that
        // one bit so the menus aren't rebuilt on every otherwise-identical emission.
        viewModel.$stopArrivals
            .map { ($0?.serviceAlerts ?? []).isEmpty }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.configureBarButtons() }
            .store(in: &cancellables)

        viewModel.$isListFiltered
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.configureBarButtons() }
            .store(in: &cancellables)
    }

    /// Haptic feedback for data loads, ported from `StopViewController`: a
    /// success tap on the first arrivals load and an error buzz whenever a fetch
    /// fails. The SwiftUI layer owns no `Application`, so this stays here.
    private func bindArrivalsFeedback() {
        viewModel.$stopArrivals
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, firstLoad else { return }
                firstLoad = false
                dataLoadFeedbackGenerator.dataLoad(.success)
            }
            .store(in: &cancellables)

        viewModel.$operationError
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.dataLoadFeedbackGenerator.dataLoad(.failed)
            }
            .store(in: &cancellables)
    }

    /// Presents the multi-question survey screen and the hero-submission error
    /// alert, driven by the view model's publishers (ported from
    /// `StopViewController.bindSurveysSink()`).
    private func bindSurveyPresentation() {
        viewModel.presentFullSurvey
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                self?.showFullSurvey(payload.survey, heroResponseID: payload.heroResponseID)
            }
            .store(in: &cancellables)

        viewModel.surveySubmissionError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                guard let self else { return }
                Task { @MainActor in
                    await AlertPresenter.show(error: error, presentingController: self)
                }
            }
            .store(in: &cancellables)
    }

    /// Surfaces alarm-flow failures the SwiftUI page can't present itself: the
    /// standard error alert for a failed create/cancel, and a Settings-guidance
    /// alert when notification permission is already denied.
    private func bindAlarmFeedback() {
        viewModel.$alarmError
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                guard let self else { return }
                Task { @MainActor in
                    await AlertPresenter.show(error: error, presentingController: self)
                }
            }
            .store(in: &cancellables)

        viewModel.$alarmPermissionDenied
            .dropFirst()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.presentAlarmPermissionDeniedAlert()
            }
            .store(in: &cancellables)
    }

    private func presentAlarmPermissionDeniedAlert() {
        let alert = UIAlertController(
            title: OBALoc(
                "stop_page.alarm_permission_denied.title",
                value: "Notifications Are Off",
                comment: "Title of the alert shown when the user tries to set a departure alarm but notifications are denied in Settings."
            ),
            message: String(
                format: OBALoc(
                    "stop_page.alarm_permission_denied.message",
                    value: "To get departure alarms, allow notifications for %@ in Settings.",
                    comment: "Body of the alert shown when the user tries to set a departure alarm but notifications are denied in Settings. %@ is the app name."
                ),
                Bundle.main.appName
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Strings.cancel, style: .cancel))
        alert.addAction(UIAlertAction(
            title: OBALoc(
                "stop_page.alarm_permission_denied.open_settings",
                value: "Open Settings",
                comment: "Button that opens the system Settings app so the user can enable notifications."
            ),
            style: .default
        ) { [weak self] _ in
            guard let self, let url = URL(string: UIApplication.openSettingsURLString) else { return }
            self.application.open(url, options: [:], completionHandler: nil)
        })
        present(alert, animated: true)
        // Reset so a later already-denied attempt re-fires the binding.
        viewModel.clearAlarmPermissionDenied()
    }

    // MARK: - Alarm Picker

    private var alarmBuilder: AlarmBuilder?
    /// The departure the open bulletin is for, so `alarmCreated` can index the
    /// alarm under it (the delegate callback doesn't carry the departure).
    private var alarmBuilderDeparture: ArrivalDeparture?

    /// Presents the same lead-time picker bulletin as
    /// `StopViewController.addAlarm(arrivalDeparture:)`; `AlarmBuilder` owns the
    /// picker UI and the create request. Also serves the Change flow: when the
    /// departure already has an alarm, the picker opens pre-selected to its
    /// current lead time and the created alarm replaces the old one.
    private func showAlarmPicker(for arrivalDeparture: ArrivalDeparture) {
        // The SwiftUI alarm affordances are gated on `canCreateAlarm`, but that
        // gate is only re-evaluated on the ~15s refresh — a departure can slip
        // inside the one-minute floor while the row (or an open trip panel) still
        // offers the button. Re-check here so the picker never opens with no
        // selectable lead time.
        guard viewModel.canCreateAlarm(for: arrivalDeparture) else { return }

        alarmBuilderDeparture = arrivalDeparture
        let existingAlarm = viewModel.alarm(for: arrivalDeparture)
        alarmBuilder = AlarmBuilder(
            arrivalDeparture: arrivalDeparture,
            application: application,
            initialMinutes: existingAlarm.map { viewModel.alarmLeadTimeMinutes($0) },
            delegate: self)
        alarmBuilder?.showBulletin(above: self)
    }

    func alarmBuilderStartedRequest(_ alarmBuilder: AlarmBuilder) {
        ProgressHUD.show()
    }

    func alarmBuilder(_ alarmBuilder: AlarmBuilder, alarmCreated alarm: Alarm) {
        if let departure = alarmBuilderDeparture {
            // `replaceAlarm` indexes the new alarm synchronously and no-ops the
            // delete when the departure had no prior alarm, so it serves both
            // the create and change flows.
            Task { await viewModel.replaceAlarm(with: alarm, for: departure) }

            if alarmBuilder.trackOnLockScreen {
                startLiveActivity(for: departure)
            }
        } else {
            viewModel.recordAlarmCreated(alarm)
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

    // MARK: - Live Activity

    func startLiveActivity(for departure: ArrivalDeparture) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let routeColorHex = departure.route.color?.toHex()
        let staticData = TripAttributes.StaticData(
            routeShortName: departure.routeShortName,
            routeHeadsign: departure.tripHeadsign ?? "",
            stopID: departure.stopID,
            routeColorHex: routeColorHex,
            regionID: application.currentRegion?.regionIdentifier ?? 0
        )

        guard let contentState = buildLiveActivityContentState(for: departure) else {
            Logger.error("Failed to build content state for Live Activity")
            return
        }

        let attributes = TripAttributes(staticData: staticData)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: .token
            )
            application.liveActivityTracker.track(activity: activity, metadata: .init(departure))
            Logger.info("Started Live Activity with ID: \(activity.id)")
            viewModel.signalLiveActivityStarted()
        } catch {
            Logger.error("Failed to start Live Activity: \(error)")
            showLiveActivityErrorAlert()
        }
    }

    private func buildLiveActivityContentState(for departure: ArrivalDeparture) -> TripAttributes.ContentState? {
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

    // MARK: - Snapshot

    /// Bridges the callback-based `MapSnapshotter` into async/await for the
    /// SwiftUI header. Mirrors `StopHeaderView`'s configuration (stop
    /// annotation, zoom, muted map) from `StopHeaderController.swift`.
    private func loadSnapshot(size: CGSize) async -> UIImage? {
        guard let stop = viewModel.stop, size.width > 0, size.height > 0 else { return nil }
        let factory = application.stopIconFactory
        // The header design is always-dark (white identity text over a dark
        // scrim), so render the map snapshot in dark style regardless of the
        // system appearance.
        let traits = traitCollection.modifyingTraits { $0.userInterfaceStyle = .dark }
        return await withCheckedContinuation { continuation in
            let snapshotter = MapSnapshotter(size: size, stopIconFactory: factory)
            snapshotter.snapshot(stop: stop, traitCollection: traits) { image in
                // `MapSnapshotter`'s internal `MKMapSnapshotter.start` completion is
                // `[weak self]`, so the wrapper must outlive the async render or the
                // completion early-returns and this continuation never resumes —
                // leaving the header permanently blank. The legacy `StopHeaderView`
                // avoids this by retaining the snapshotter in a stored property; here
                // there's no `self` to hold it, so extend its lifetime through the
                // callback explicitly.
                withExtendedLifetime(snapshotter) {
                    continuation.resume(returning: image)
                }
            }
        }
    }

    // MARK: - Previewable

    private var inPreviewMode = false

    func enterPreviewMode() {
        inPreviewMode = true
        configureBarButtons()
    }

    func exitPreviewMode() {
        inPreviewMode = false
        configureBarButtons()
    }
}

// MARK: - Nav Bar Items & Menus

private extension StopPageViewController {
    /// Ported from `StopViewController.configureTabBarButtons()`, minus the Sort
    /// menu — the SwiftUI mode toggle supersedes it (spec decision).
    func configureBarButtons() {
        // A peek preview shows a bare, non-interactive glance (no chrome).
        guard !inPreviewMode else {
            navigationItem.rightBarButtonItems = nil
            return
        }

        // The titles double as the VoiceOver labels for these image-only bar
        // buttons, so they must be localized, human-readable strings — the
        // filter's on/off state rides in `accessibilityValue` rather than
        // being baked into the label.
        let filterIsOn = viewModel.stopPreferences.hasHiddenRoutes && viewModel.isListFiltered
        let filterButtonImage = UIImage(systemName: filterIsOn ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")

        let filterMenuButton = UIBarButtonItem(title: Strings.filter, image: filterButtonImage, menu: filterMenu())
        filterMenuButton.accessibilityValue = filterIsOn
            ? OBALoc("stop_page.filter.a11y_on", value: "on", comment: "VoiceOver value of the route-filter bar button when the filter is active.")
            : OBALoc("stop_page.filter.a11y_off", value: "off", comment: "VoiceOver value of the route-filter bar button when the filter is inactive.")
        let moreMenuButton = UIBarButtonItem(title: Strings.more, image: UIImage(systemName: "ellipsis.circle"), menu: pulldownMenu())
        let schedulesBtn = UIBarButtonItem(image: UIImage(systemName: "calendar"), style: .plain, target: self, action: #selector(showScheduleForStop))
        schedulesBtn.accessibilityLabel = Strings.schedules

        navigationItem.rightBarButtonItems = [moreMenuButton, filterMenuButton, schedulesBtn]
    }

    /// The "More" pulldown: File / Location / Help. No Sort submenu (the toggle
    /// supersedes it).
    func pulldownMenu() -> UIMenu {
        UIMenu(children: [fileMenu(), locationMenu(), helpMenu()])
    }

    func filterMenu() -> UIMenu {
        let allRoutesTitle = OBALoc("stops_controller.filter.all_routes", value: "All Routes", comment: "A menu item on a Stop page that toggles the visible list of transit vehicles from a filtered list to all of the list items. e.g. a stop serves routes 1, 2, and 3. The user has filtered the stop to only show route 3. Chooosing this item will show 1, 2, and 3 again.")
        let filteredRoutesTitle = OBALoc("stops_controller.filter.filtered_routes", value: "Filtered Routes", comment: "A menu item on a Stop page that toggles the visible list of transit vehicles from a list of all items to a filtered list. e.g. a stop serves routes 1, 2, and 3. The user wants to only view route 3. Choosing this item would show that subset of routes.")

        let showAll = UIAction(title: allRoutesTitle) { [unowned self] _ in
            if self.viewModel.isListFiltered {
                self.viewModel.isListFiltered = false
            }
        }

        let showFiltered = UIAction(title: filteredRoutesTitle) { [unowned self] _ in
            self.viewModel.isListFiltered = true
            self.filter()
        }

        guard let stop = viewModel.stop else {
            return UIMenu(children: [showAll, showFiltered])
        }

        var children = [showAll]

        if stop.routes.count > 1 {
            if viewModel.isListFiltered && viewModel.stopPreferences.hasHiddenRoutes {
                showFiltered.image = UIImage(systemName: "checkmark")
            } else {
                showAll.image = UIImage(systemName: "checkmark")
            }

            children.append(showFiltered)
        }

        return UIMenu(children: children)
    }

    func fileMenu() -> UIMenu {
        let bookmarkAction = UIAction(title: Strings.addBookmark, image: UIImage(systemName: "bookmark")) { [unowned self] _ in
            self.showBookmarkEditor(for: nil)
        }

        let alertsAction = UIAction(title: Strings.serviceAlerts, image: UIImage(systemName: "exclamationmark.circle")) { [unowned self] _ in
            let controller = ServiceAlertListController(application: self.application, serviceAlerts: self.viewModel.stopArrivals?.serviceAlerts ?? [])
            self.application.viewRouter.navigate(to: controller, from: self)
        }

        // Disable the alerts action if there are no service alerts.
        if (viewModel.stopArrivals?.serviceAlerts ?? []).isEmpty {
            alertsAction.attributes = .disabled
        }

        return UIMenu(title: "File", options: .displayInline, children: [bookmarkAction, alertsAction])
    }

    func locationMenu() -> UIMenu {
        let nearbyAction = UIAction(title: OBALoc("stops_controller.nearby_stops", value: "Nearby Stops", comment: "Title of the row that will show stops that are near this one."), image: UIImage(systemName: "location")) { [unowned self] _ in
            guard let coordinate = self.viewModel.stop?.coordinate else { return }
            let nearbyController = NearbyStopsViewController(coordinate: coordinate, application: self.application)
            self.application.viewRouter.navigate(to: nearbyController, from: self)
        }

        var walkingDirectionActions: [UIMenuElement] = []

        if let stop = viewModel.stop {
            if let appleMapsURL = AppInterop.appleMapsWalkingDirectionsURL(coordinate: stop.coordinate) {
                let appleMaps = UIAction(title: OBALoc("stops_controller.walking_directions_apple", value: "Walking Directions (Apple Maps)", comment: "Button that launches Apple's maps.app with walking directions to this stop")) { [unowned self] _ in
                    self.application.open(appleMapsURL, options: [:], completionHandler: nil)
                }
                walkingDirectionActions.append(appleMaps)
            }

            #if !targetEnvironment(simulator)
            // Display Google Maps app link, only if Google Maps is installed.
            if let googleMapsURL = AppInterop.googleMapsWalkingDirectionsURL(coordinate: stop.coordinate),
               self.googleMapsAvailable {
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

    func helpMenu() -> UIMenu {
        let reportButton = UIAction(title: OBALoc("stops_controller.report_problem", value: "Report a Problem", comment: "Button that launches the 'Report Problem' UI."), image: UIImage(systemName: "exclamationmark.bubble")) { [unowned self] _ in
            self.showReportProblem()
        }

        return UIMenu(title: "Help", options: .displayInline, children: [reportButton])
    }
}

// MARK: - Navigation Out (ported presentation flows)

private extension StopPageViewController {
    @objc func showScheduleForStop() {
        let scheduleVC = ScheduleForStopViewController(stopID: viewModel.stopID, application: application)
        present(scheduleVC, animated: true)
    }

    func showScheduleForRoute(for arrivalDeparture: ArrivalDeparture) {
        let scheduleVC = ScheduleForRouteViewController(routeID: arrivalDeparture.routeID, application: application)
        present(scheduleVC, animated: true)
    }

    /// Opens the bookmark editor. `nil` starts the stop-level "Add Bookmark"
    /// workflow; a departure jumps straight into editing a trip bookmark. Ports
    /// `StopViewController.addBookmark(sender:)` and `addBookmark(arrivalDeparture:)`.
    func showBookmarkEditor(for arrivalDeparture: ArrivalDeparture?) {
        if let arrivalDeparture {
            let bookmarkController = EditBookmarkViewController(application: application, arrivalDeparture: arrivalDeparture, bookmark: nil, delegate: self)
            let navigation = UINavigationController(rootViewController: bookmarkController)
            application.viewRouter.present(navigation, from: self)
        } else {
            guard let stop = viewModel.stop else { return }
            let bookmarkController = AddBookmarkViewController(application: application, stop: stop, preloadedArrivals: viewModel.stopArrivals?.arrivalsAndDepartures, delegate: self)
            let navigation = application.viewRouter.buildNavigation(controller: bookmarkController)
            application.viewRouter.present(navigation, from: self, isModal: true)
        }
    }

    /// Route Filter workflow. Presents the SwiftUI `StopPreferencesWrappedView` in
    /// a `UIHostingController` (ported from `StopViewController.filter()`).
    func filter() {
        guard let stop = viewModel.stop else { return }

        let hiddenRoutes = Set(viewModel.stopPreferences.hiddenRoutes)
        let stopPreferencesView = StopPreferencesWrappedView(stop, initialHiddenRoutes: hiddenRoutes, delegate: self)
            .environment(\.coreApplication, application)
        present(UIHostingController(rootView: stopPreferencesView), animated: true)
    }

    /// Opens walking directions to the stop from the header's walk pill. Reuses
    /// the `locationMenu()` availability logic: Apple Maps always, Google Maps
    /// only when installed. One available app opens directly; more than one
    /// presents an action sheet to disambiguate.
    func showWalkingDirections() {
        guard let coordinate = viewModel.stop?.coordinate else { return }

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
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(origin: view.center, size: .zero)
        }
        present(sheet, animated: true)
    }

    func showReportProblem() {
        guard let stop = viewModel.stop else { return }

        let reportProblemController = ReportProblemViewController(application: application, stop: stop)
        let navigation = application.viewRouter.buildNavigation(controller: reportProblemController)
        application.viewRouter.present(navigation, from: self, isModal: true)
    }

    // MARK: - Surveys

    func showFullSurvey(_ survey: Survey, heroResponseID: String? = nil) {
        let surveyVC = SurveyViewController(
            survey: survey,
            surveyService: application.surveyService,
            stop: viewModel.stop,
            stopID: viewModel.stopID,
            stopLocation: viewModel.stop?.coordinate,
            heroResponseID: heroResponseID
        )
        let nav = UINavigationController(rootViewController: surveyVC)
        present(nav, animated: true)
    }

    func showExternalSurveyError() {
        let alert = UIAlertController(
            title: OBALoc("stop_controller.external_survey_error.title", value: "Can't Open Survey", comment: "Title shown when an external survey link cannot be opened"),
            message: OBALoc("stop_controller.external_survey_error.message", value: "This survey link couldn't be opened. Please try again later.", comment: "Message shown when an external survey link cannot be opened"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Strings.ok, style: .default))
        present(alert, animated: true)
    }

    // MARK: - Donations

    func showDonationUI() {
        guard
            application.donationsManager.donationsEnabled,
            let donationModel = application.donationsManager.buildObservableDonationModel()
        else {
            return
        }

        let learnMoreView = DonationLearnMoreView()
            .environmentObject(donationModel)
            .environmentObject(AnalyticsModel(application.analytics))

        present(UIHostingController(rootView: learnMoreView), animated: true)
    }

    /// Presents the "please don't dismiss" action sheet. `onHide` is invoked only
    /// when the user actually hides the card (dismiss or remind-later), so the
    /// SwiftUI page can drop the donation section immediately. Ports
    /// `StopViewController.showDonationDismissUI()` (whose `refresh()` re-render is
    /// replaced by the `onHide` callback).
    func showDonationDismissUI(onHide: @escaping () -> Void) {
        let alertController = UIAlertController(
            title: Strings.donationsDismissAlertTitle,
            message: Strings.donationsDismissAlertMessage,
            preferredStyle: .actionSheet
        )

        alertController.addAction(
            title: Strings.donationsDismissAlertButtonDismiss,
            style: .destructive
        ) { [weak self] _ in
            self?.application.donationsManager.dismissDonationsRequests()
            onHide()
        }

        alertController.addAction(
            title: Strings.donationsDismissAlertButtonRemindLater,
            style: .default
        ) { [weak self] _ in
            self?.application.donationsManager.remindUserLater()
            onHide()
        }

        alertController.addAction(title: Strings.cancel, style: .cancel, handler: nil)

        // An unanchored action sheet is a hard crash on iPad. The donation card has no
        // stable UIKit source view (it lives inside the SwiftUI list), so anchor to the
        // middle of the page, as `showWalkingDirections()` does.
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(origin: view.center, size: .zero)
        }

        present(alertController, animated: true)
    }
}

// MARK: - BookmarkEditorDelegate

extension StopPageViewController {
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

extension StopPageViewController {
    func stopPreferences(stopID: StopID, updated stopPreferences: StopPreferences) {
        viewModel.updateStopPreferences(stopPreferences)
    }
}

// MARK: - Trip Preview

/// Lazily-built UIKit preview for row long-presses; the `TripViewController` is
/// constructed only when SwiftUI actually presents the context-menu preview.
struct TripViewControllerPreview: UIViewControllerRepresentable {
    let departure: ArrivalDeparture
    let application: Application

    func makeUIViewController(context: Context) -> TripViewController {
        TripViewController(application: application, arrivalDeparture: departure)
    }

    func updateUIViewController(_ uiViewController: TripViewController, context: Context) {}
}
