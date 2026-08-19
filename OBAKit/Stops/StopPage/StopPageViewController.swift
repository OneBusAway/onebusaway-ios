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
    Idleable,
    Previewable,
    StopSheetCollapsibleContent,
    StopSheetSelfChromedContent {

    let application: Application
    let viewModel: StopViewModel
    private var cancellables = Set<AnyCancellable>()

    private lazy var actionPresenter = StopPageActionPresenter(
        application: application,
        presentingController: { [weak self] in self }
    )

    /// Called when the user taps the sheet's close button. Set by the map view controller
    /// immediately after creating this controller; no-op when `showToolbarOnBottom` is false.
    var onClose: (() -> Void)?

    /// Set by a host that owns a map, so a trip opened from this page can point
    /// that map at the trip. Left nil where this page was pushed full-screen —
    /// there is no map behind it to focus. Stored on the presenter, which is what
    /// actually pushes the trip page for both presentations.
    var onTripPagePush: ((TripPageViewController) -> Void)? {
        get { actionPresenter.onTripPagePush }
        set { actionPresenter.onTripPagePush = newValue }
    }

    /// Only the sheet-configured page draws its own header; the pushed variant keeps its
    /// navigation-bar chrome.
    var providesOwnSheetChrome: Bool { showsBottomToolbar }

    /// Opens the SwiftUI trip page — the row context menu's "Show Trip Details".
    func showTripPage(for arrivalDeparture: ArrivalDeparture) {
        actionPresenter.showTripPage(for: arrivalDeparture, originTitle: viewModel.stop?.name)
    }

    private lazy var dataLoadFeedbackGenerator = DataLoadFeedbackGenerator(application: application)

    /// Gates the one-shot success haptic to the first arrivals load, matching
    /// `StopViewController.bindArrivalsSink()`; later refreshes are silent.
    private var firstLoad = true

    var bookmarkContext: Bookmark? {
        get { viewModel.bookmarkContext }
        set { viewModel.bookmarkContext = newValue }
    }

    var transferContext: TransferContext? {
        get { viewModel.transferContext }
        set { viewModel.transferContext = newValue }
    }

    /// `true` when this instance was built for the map's sheet presentation: the header goes
    /// light and compact and the chrome moves to a bottom toolbar. Fixed at init — a controller
    /// never migrates between presentations — so the pushed screen is unreachable from here.
    private let showToolbarOnBottom: Bool

    /// The map's focus channel, when this page was presented as the map's stop
    /// sheet. Inert for every pushed presentation.
    ///
    /// Stored on the controller and re-threaded through `installRootView()`,
    /// exactly like `isAtTip` — writing `rootView.mapFocus` alone would be
    /// silently dropped by the next `installRootView()` (e.g. from
    /// `exitPreviewMode`).
    private var mapFocus = StopMapFocus()

    /// Attaches the map's focus channel so the sheet header's route chips can decorate
    /// themselves from — and write into — the same object the map layer reads. Called once, by
    /// the map view controller, immediately after creating this instance for its sheet.
    func attach(focus: StopMapFocus) {
        mapFocus = focus
        installRootView()
    }

    convenience init(application: Application, stop: Stop, showToolbarOnBottom: Bool = false) {
        self.init(application: application, stopID: stop.id, stop: stop, showToolbarOnBottom: showToolbarOnBottom)
    }

    convenience init(application: Application, stopID: StopID, showToolbarOnBottom: Bool = false) {
        self.init(application: application, stopID: stopID, stop: nil, showToolbarOnBottom: showToolbarOnBottom)
    }

    private init(application: Application, stopID: StopID, stop: Stop?, showToolbarOnBottom: Bool) {
        self.application = application
        self.viewModel = StopViewModel(application: application, stopID: stopID, stop: stop)
        self.showToolbarOnBottom = showToolbarOnBottom

        // Seed with placeholder closures; `self` isn't available until super.init
        // returns, so the real handler (which captures `self`) is installed below.
        super.init(rootView: StopPageRootView(
            viewModel: viewModel,
            userDefaults: application.userDefaults,
            snapshotLoader: { _ in nil },
            navigation: Self.placeholderNavigation,
            formatters: application.formatters,
            mapFocus: mapFocus
        ))

        installRootView()

        hidesBottomBarWhenPushed = false
    }

    /// Builds the SwiftUI root with the real navigation handler. Called again whenever
    /// `showsBottomToolbar` changes — which only happens on entering or leaving preview mode,
    /// before the rider has interacted with the page, so the `@State` reset costs nothing — and
    /// also by `attach(focus:)`, which re-threads `mapFocus` through a fresh root the same way.
    private func installRootView() {
        rootView = StopPageRootView(
            viewModel: viewModel,
            userDefaults: application.userDefaults,
            snapshotLoader: { [weak self] size in
                guard let self else { return nil }
                return await self.loadSnapshot(size: size)
            },
            navigation: makeNavigationHandler(),
            formatters: application.formatters,
            mapFocus: mapFocus,
            showToolbarOnBottom: showsBottomToolbar,
            isCollapsed: isAtTip
        )
    }

    /// `true` while the sheet showing this page sits at its `.tip` detent. Stored rather than
    /// derived so `installRootView()` — which runs again on preview-mode changes — rebuilds the
    /// root with the detent the sheet is actually at instead of resetting it to expanded.
    private var isAtTip = false

    /// Called by `StopSheetPresenter` when the panel's detent changes. At `.tip` the sheet is
    /// barely onscreen: the bottom toolbar goes away and the header collapses to the stop name
    /// and its close button, which is all the detent has room for.
    func setAtTip(_ isAtTip: Bool) {
        guard self.isAtTip != isAtTip else { return }
        self.isAtTip = isAtTip
        rootView.isCollapsed = isAtTip
    }

    /// Suppressed in preview mode: a peek is a bare glance, the same reason `configureBarButtons()`
    /// clears the nav-bar items there. Internal so `StopPagePresentationTests` can assert which
    /// presentation an instance was built for.
    var showsBottomToolbar: Bool {
        showToolbarOnBottom && !inPreviewMode
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
        guard let stop = viewModel.stop else { return }
        self.userActivity = actionPresenter.makeUserActivity(stop: stop)
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
        shareTrip: { _ in },
        showAlarmPicker: { _ in },
        startLiveActivity: { _ in },
        showExternalSurveyError: {},
        showDonation: {},
        dismissDonation: { _ in },
        makeTripPreview: { _ in AnyView(EmptyView()) },
        showRouteFilter: {},
        showServiceAlerts: {},
        showNearbyStops: {},
        showReportProblem: {},
        closeSheet: {}
    )

    private func makeNavigationHandler() -> StopPageNavigationHandler {
        actionPresenter.makeNavigationHandler(viewModel: viewModel, closeSheet: { [weak self] in
            self?.onClose?()
        })
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

        viewModel.$arrivalDepartureFilter
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
        actionPresenter.showAlarmPermissionDeniedAlert(onPresented: { [weak self] in
            self?.viewModel.clearAlarmPermissionDenied()
        })
    }

    // MARK: - Alarm Picker

    private func showAlarmPicker(for arrivalDeparture: ArrivalDeparture) {
        actionPresenter.showAlarmPicker(for: arrivalDeparture, viewModel: viewModel)
    }

    // MARK: - Live Activity

    private func startLiveActivity(for departure: ArrivalDeparture) {
        actionPresenter.startLiveActivity(for: departure, viewModel: viewModel)
    }

    // MARK: - Snapshot

    /// Bridges the callback-based `MapSnapshotter` into async/await for the
    /// SwiftUI header.
    private func loadSnapshot(size: CGSize) async -> UIImage? {
        guard let stop = viewModel.stop else { return nil }
        return await actionPresenter.loadSnapshot(stop: stop, size: size, traitCollection: traitCollection)
    }

    // MARK: - Previewable

    private var inPreviewMode = false

    func enterPreviewMode() {
        inPreviewMode = true
        configureBarButtons()
        refreshBottomToolbar()
    }

    func exitPreviewMode() {
        inPreviewMode = false
        configureBarButtons()
        refreshBottomToolbar()
    }

    /// Rebuilds the SwiftUI root so the toolbar appears or disappears with preview mode. Scoped
    /// to the sheet: pushed controllers also enter and exit previews (Recents, Bookmarks, the map
    /// drawer), and reinstalling their root view would reset page `@State` for no visible gain.
    private func refreshBottomToolbar() {
        guard showToolbarOnBottom else { return }
        installRootView()
    }
}

// MARK: - Nav Bar Items & Menus

private extension StopPageViewController {
    /// Ported from `StopViewController.configureTabBarButtons()`, minus the Sort
    /// menu — the SwiftUI mode toggle supersedes it (spec decision).
    func configureBarButtons() {
        guard !inPreviewMode else {
            navigationItem.rightBarButtonItems = nil
            return
        }

        // Sheet presentation: every control lives in SwiftUI — `StopPageToolbar` at the bottom
        // and the header's own close button — and `StopSheetPresenter` hides the navigation bar
        // outright, so there is nowhere for bar items to go.
        if showToolbarOnBottom {
            navigationItem.rightBarButtonItems = nil
            return
        }

        // The titles double as the VoiceOver labels for these image-only bar
        // buttons, so they must be localized, human-readable strings — the
        // filter's on/off state rides in `accessibilityValue` rather than
        // being baked into the label.
        //
        // This glyph fills for either filter: the bar button owns `filterMenu()`,
        // which contains both the route section and the Departure Type submenu, so
        // hidden routes or a non-default Departure Type both mean rows are being
        // held back and either should show up here. The sheet presentation's
        // toolbar deliberately does *not* mirror this — see `StopPageToolbar`,
        // where the two filters are siblings and each carries its own state.
        let filterIsOn = (viewModel.stopPreferences.hasHiddenRoutes && viewModel.isListFiltered)
            || viewModel.arrivalDepartureFilter != .all
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

        var routeChildren = [showAll]

        if let stop = viewModel.stop {
            if stop.routes.count > 1 {
                // `state`, not a checkmark image: it draws the same checkmark but
                // is also what VoiceOver reads as "selected". An image is
                // decoration the accessibility layer never announces.
                let routesAreFiltered = viewModel.isListFiltered && viewModel.stopPreferences.hasHiddenRoutes
                showFiltered.state = routesAreFiltered ? .on : .off
                showAll.state = routesAreFiltered ? .off : .on

                routeChildren.append(showFiltered)
            }
        } else {
            routeChildren.append(showFiltered)
        }

        let routesSection = UIMenu(options: .displayInline, children: routeChildren)
        return UIMenu(children: [routesSection, departureFilterMenu()])
    }

    /// The Departure Type submenu: everything, real-time only, or scheduled
    /// only. The same choices as the legacy page's `arrivalDepartureFilterMenu()`,
    /// persisted app-wide through the shared view model.
    func departureFilterMenu() -> UIMenu {
        let currentFilter = viewModel.arrivalDepartureFilter
        let actions = ArrivalDepartureFilter.allCases.map { filter -> UIAction in
            let action = UIAction(title: filter.displayTitle) { [unowned self] _ in
                self.viewModel.updateArrivalDepartureFilter(filter)
            }
            action.state = filter == currentFilter ? .on : .off
            return action
        }

        let menuTitle = OBALoc("stop_controller.arrival_filter.menu_title", value: "Departure Type", comment: "Title for the menu that filters departures by data type")
        return UIMenu(title: menuTitle, image: Icons.departureType(isActive: currentFilter != .all), children: actions)
    }

    func fileMenu() -> UIMenu {
        let bookmarkAction = UIAction(title: Strings.addBookmark, image: UIImage(systemName: "bookmark")) { [unowned self] _ in
            self.showBookmarkEditor(for: nil)
        }

        let alertsAction = UIAction(title: Strings.serviceAlerts, image: UIImage(systemName: "exclamationmark.circle")) { [unowned self] _ in
            self.showServiceAlerts()
        }

        // Disable the alerts action if there are no service alerts.
        if (viewModel.stopArrivals?.serviceAlerts ?? []).isEmpty {
            alertsAction.attributes = .disabled
        }

        return UIMenu(title: "File", options: .displayInline, children: [bookmarkAction, alertsAction])
    }

    func locationMenu() -> UIMenu {
        let nearbyAction = UIAction(title: OBALoc("stops_controller.nearby_stops", value: "Nearby Stops", comment: "Title of the row that will show stops that are near this one."), image: UIImage(systemName: "location")) { [unowned self] _ in
            self.showNearbyStops()
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
               self.actionPresenter.googleMapsAvailable(coordinate: stop.coordinate) {
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
        actionPresenter.showScheduleForStop(stopID: viewModel.stopID)
    }

    func showScheduleForRoute(for arrivalDeparture: ArrivalDeparture) {
        actionPresenter.showScheduleForRoute(arrivalDeparture)
    }

    /// Opens the bookmark editor. `nil` starts the stop-level "Add Bookmark"
    /// workflow; a departure jumps straight into editing a trip bookmark.
    func showBookmarkEditor(for arrivalDeparture: ArrivalDeparture?) {
        actionPresenter.showBookmarkEditor(
            for: arrivalDeparture,
            stop: viewModel.stop,
            preloadedArrivals: viewModel.stopArrivals?.arrivalsAndDepartures
        )
    }

    /// Route Filter workflow.
    func filter() {
        guard let stop = viewModel.stop else { return }
        actionPresenter.showRouteFilter(
            stop: stop,
            hiddenRoutes: Set(viewModel.stopPreferences.hiddenRoutes),
            onUpdate: { [weak self] prefs in self?.viewModel.updateStopPreferences(prefs) }
        )
    }

    /// Opens walking directions to the stop.
    func showWalkingDirections() {
        guard let coordinate = viewModel.stop?.coordinate else { return }
        actionPresenter.showWalkingDirections(coordinate: coordinate)
    }

    /// Pushes the service-alert list.
    func showServiceAlerts() {
        actionPresenter.showServiceAlerts(viewModel.stopArrivals?.serviceAlerts ?? [])
    }

    /// Pushes the nearby-stops list.
    func showNearbyStops() {
        guard let coordinate = viewModel.stop?.coordinate else { return }
        actionPresenter.showNearbyStops(coordinate: coordinate)
    }

    func showReportProblem() {
        guard let stop = viewModel.stop else { return }
        actionPresenter.showReportProblem(stop: stop)
    }

    // MARK: - Surveys

    func showFullSurvey(_ survey: Survey, heroResponseID: String? = nil) {
        actionPresenter.showFullSurvey(survey, heroResponseID: heroResponseID, stop: viewModel.stop, stopID: viewModel.stopID)
    }

    func showExternalSurveyError() {
        actionPresenter.showExternalSurveyError()
    }

    // MARK: - Donations

    func showDonationUI() {
        actionPresenter.showDonation()
    }

    /// Presents the "please don't dismiss" action sheet.
    func showDonationDismissUI(onHide: @escaping () -> Void) {
        actionPresenter.showDonationDismiss(onHide: onHide)
    }
}
