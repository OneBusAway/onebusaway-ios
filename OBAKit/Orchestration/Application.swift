//
//  Application.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import CoreTelephony
import CoreLocation
import OBAKitCore
import SafariServices
import MapKit
import SwiftUI
import TipKit

// MARK: - Protocols

@objc(OBAApplicationDelegate)
public protocol ApplicationDelegate {

    /// Provides access to the `UIApplication` object.
    @objc var uiApplication: UIApplication? { get }

    /// This method is called when the delegate should reload the `rootViewController`
    /// of the app's window. This is typically done in response to permissions changes.
    @objc func applicationReloadRootInterface(_ app: Application)

    /// This proxies the `isIdleTimerDisabled` property on `UIApplication`, which prevents
    /// the screen from turning off when it is set to `true`.
    @objc(idleTimerDisabled) var isIdleTimerDisabled: Bool { get set }

    /// This proxies the `isRegisteredForRemoteNotifications` property on `UIApplication`.
    @objc(registeredForRemoteNotifications) var isRegisteredForRemoteNotifications: Bool { get }

    /// Proxies `UIApplication.canOpenURL()`
    /// - Parameter url: The URL that we are checking can be opened.
    @objc func canOpenURL(_ url: URL) -> Bool

    /// Proxies the equivalent method on `UIApplication`
    @objc func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any], completionHandler completion: ((Bool) -> Void)?)

    /// An optional property that allows the delegate to specify libraries that require attribution within this app.
    @objc optional var credits: [String: String] { get }

    /// Implement this method in your delegate to add a 'Crash' button to the More tab of the app.
    ///
    /// Tapping the 'Crash' button will crash the app, which is useful for testing your integration of third-party
    /// crash reporter libraries, like Crashlytics.
    @objc optional func performTestCrash()
}

// MARK: - Application Class

/// Responsible for creating the entire application 'stack': API service, regions, push notifications, UI, and everything else that makes the app run.
///
/// - Note: See `OBAKitCore.CoreApplication` for a version of this class suitable for running in an application extension.
@objc(OBAApplication)
public class Application: CoreApplication, PushServiceDelegate {

    // MARK: - Private Properties

    /// App configuration parameters: API keys, region server, user UUID, and other
    /// configuration values.
    private let config: AppConfig

    // MARK: - Public Properties

    lazy var donationsManager = DonationsManager(
        bundle: applicationBundle,
        userDefaults: userDefaults,
        obacoService: obacoService,
        analytics: analytics,
        appLaunchCount: { [userDataStore] in userDataStore.appLaunchCount }
    )

    @MainActor
    lazy var promptCoordinator = PromptCoordinator(
        userDefaults: userDefaults,
        notificationCenter: notificationCenter
    )

    @MainActor
    lazy var reviewPromptPolicy = ReviewPromptPolicy(
        userDefaults: userDefaults,
        bundle: applicationBundle
    )

    /// Responsible for figuring out how to navigate between view controllers.
    @MainActor
    lazy var viewRouter = ViewRouter(application: self)

    /// Responsible for creating stop 'badges' for the map.
    lazy var stopIconFactory = StopIconFactory(iconSize: ThemeMetrics.defaultMapAnnotationSize, themeColors: ThemeColors.shared)

    lazy var mapRegionManager = MapRegionManager(application: self)

    lazy var searchManager = SearchManager(application: self)

    lazy var toastManager = ToastManager()

    @MainActor
    lazy var walkingSpeedManager = WalkingSpeedManager(userDataStore: userDataStore)

    /// Owns the rider's destination proximity alerts.
    ///
    /// `lazy` only because it needs a fully-initialized `self`; `init` forces it
    /// immediately, and the comment there explains why it must not wait for a
    /// first use that may never come.
    @MainActor
    public private(set) lazy var proximityAlertManager = ProximityAlertManager(
        locationService: locationService,
        userDataStore: userDataStore,
        regionIDProvider: { [weak self] in self?.regionsService.currentRegion?.regionIdentifier }
    )

    @MainActor
    lazy var bikeModeManager = BikeModeManager(userDataStore: userDataStore)

    @objc lazy var userActivityBuilder = UserActivityBuilder(application: self)

    /// Handles all deep-linking into the app.
    @objc public private(set) lazy var appLinksRouter: AppLinksRouter? = makeAppLinksRouter()

    private func makeAppLinksRouter() -> AppLinksRouter? {
        let router = AppLinksRouter(application: self)

        router?.showStopDestinationHandler = { [weak self] destination in
            self?.queueOrOpenStop(destination)
        }

        router?.showArrivalDepartureDeepLink = { [weak self] deepLink in
            guard let self, let apiService = self.apiService else {
                return
            }

            Task(priority: .userInitiated) { @MainActor in
                ProgressHUD.show()

                do {
                    let arrDep = try await apiService.getTripArrivalDepartureAtStop(stopID: deepLink.stopID, tripID: deepLink.tripID, serviceDate: deepLink.serviceDate, vehicleID: deepLink.vehicleID, stopSequence: deepLink.stopSequence).entry

                    self.withPushableTopViewController { from in
                        self.viewRouter.navigateTo(
                            arrivalDeparture: arrDep,
                            from: from,
                            destinationStopID: deepLink.destinationStopID
                        )
                    }
                } catch {
                    await self.displayError(error)
                }

                ProgressHUD.dismiss()
            }
        }

        return router
    }

    /// The application delegate object.
    @objc public weak var delegate: ApplicationDelegate?

    /// Keeps the bookmarks widget's timeline in step with the bookmark store, no
    /// matter which screen performed the write.
    ///
    /// Eagerly constructed rather than `lazy`, and held for the app's lifetime:
    /// it exists purely for the side effect of observing `.bookmarksDidChange`,
    /// so a lazy property nobody reads would never start observing, and a
    /// shorter-lived owner would stop refreshing the widget the moment its
    /// screen went away.
    let bookmarkWidgetRefresher: BookmarkWidgetRefresher

    /// Synchronizes bookmark changes to the Apple Watch companion app.
    public private(set) var bookmarkWatchSyncSender: BookmarkWatchSyncSender?

    /// Mirrors the resolved current region into the app-group suite so the
    /// widget extension — which cannot see this process's custom regions — can
    /// read it. Retained here because `RegionsService` holds delegates weakly.
    private var resolvedRegionPersister: ResolvedRegionPersister?

    /// Created in `application(_:didFinishLaunching:)`, so only the launched app refreshes Shortcuts.
    private var appShortcutParametersRefresher: AppShortcutParametersRefresher?

    // MARK: - Init

    /// Creates a new `Application` object.
    /// - Parameter config: A configuration object that determines the characteristics of this app.
    @objc public init(config: AppConfig) {
        self.config = config

        analytics = config.analytics
        bookmarkWidgetRefresher = BookmarkWidgetRefresher()

        super.init(config: config)

        bookmarkWatchSyncSender = BookmarkWatchSyncSender(
            userDataStore: userDataStore,
            regionsService: regionsService
        )

        resolvedRegionPersister = ResolvedRegionPersister(
            regionsService: regionsService,
            store: ResolvedRegionStore(userDefaults: userDefaults)
        )

        // Force the proximity alert manager now instead of leaving it to a first
        // use that may never come. A geofence crossing relaunches a terminated
        // app, and Core Location delivers the queued region event to whatever
        // `LocationService` delegates exist once launch finishes — a launch on
        // which no screen is ever built and nothing touches this property.
        // Constructing it here registers the delegate, and re-arms the regions,
        // before that event lands.
        _ = proximityAlertManager

        configureAppearanceProxies()
        observeShortcutLifecycle()
    }

    private func configureTipKit() {
        // Shows all tips all the time, regardless of display frequency or
        // invalidation state. Used by UI tests to make tip presentation
        // deterministic. Must be called before `Tips.configure()`.
        // https://developer.apple.com/documentation/tipkit/tips/showalltipsfortesting()
        #if DEBUG
        if ProcessInfo.processInfo.environment["TEST_SHOW_ALL_TIPS"] == "1" {
            Tips.showAllTipsForTesting()
        }
        #endif

        do {
            try Tips.configure([
                .displayFrequency(.hourly),
                .datastoreLocation(.applicationDefault)
            ])
        } catch {
            Logger.error("Failed to configure TipKit: \(error)")
        }
    }

    // MARK: - Onboarding/Data Migration

    /// Returns whether we should prompt the user to perform a data migration.
    /// If the user has performed the migration before, this returns `false`.
    public var shouldPerformMigration: Bool {
        DataMigrator.standard.shouldPerformMigration
    }

    /// When true, this means that the application's user defaults contain data that can be migrated into a modern format.
    public var hasDataToMigrate: Bool {
        DataMigrator.standard.hasDataToMigrate
    }

    /// If data exists to migrate, this method will prompt the user about whether they wish to migrate data from an old format to the new format.
    @MainActor
    public func performDataMigration() {
        let migrationView = UIHostingController(
            rootView:
                DataMigrationView()
                .environment(\.coreApplication, self)
        )

        if let topViewController {
            self.viewRouter.present(migrationView, from: topViewController, isModal: true)
        }
    }

    // MARK: - UI

    /// Requests that the delegate reloads the application user interface in
    /// response to major state changes, like permission changes or the selected
    /// region transitioning from nil -> not-nil.
    public func reloadRootUserInterface() {
        delegate?.applicationReloadRootInterface(self)
    }

    // MARK: - App Crashes

    /// Returns `true` if the delegate implements the `performTestCrash()` method.
    ///
    /// Tapping the 'Crash' button will crash the app, which is useful for testing your integration of third-party
    /// crash reporter libraries, like Crashlytics.
    /// - Note: This is not limited to the Simulator or to Debug builds. It returns `true` on
    ///   devices and in Release builds whenever the delegate implements `performTestCrash()`,
    ///   which both shipping app delegates do. Users reach the Settings row that calls it only
    ///   after they turn on Debug mode.
    var shouldShowCrashButton: Bool {
        guard let delegate = delegate as? NSObject & ApplicationDelegate else {
            return false
        }
        return delegate.performTestCrash != nil
    }

    /// Crashes the app by calling the appropriate delegate method.
    ///
    /// Useful for testing Crashlytics integration, for example.
    func performTestCrash() {
        guard shouldShowCrashButton else { return }
        delegate?.performTestCrash?()
    }

    // MARK: - Cellular Data

    /// Long-lived instance so `restrictedState` has time to resolve from `.unknown`.
    private let cellularData = CTCellularData()

    /// Whether the user has disabled cellular data for this app in iOS Settings.
    var isCellularDataRestricted: Bool {
        return cellularData.restrictedState == .restricted
    }

    // MARK: - Push Notifications

    /// An optional property that contains this app's configured push notifications service.
    public private(set) var pushService: PushService?

    /// Keeps this device's APNs token registered with the current region's OBACloud server so
    /// agencies can send service-alert push notifications to it. See #1204.
    public private(set) lazy var pushRegistrationManager = PushRegistrationManager(
        obacoServiceProvider: { [weak self] in self?.obacoService },
        userDefaults: userDefaults,
        testDeviceProvider: { [weak self] in
            // "Test users only" audience: agencies preview an alert push against flagged
            // devices before sending it to everyone. Debug builds always qualify; release
            // builds qualify via the Debug Mode switch in Settings. Either way, the device
            // only registers as a test device once a Test Device Name is set in the Debug
            // settings.
            #if DEBUG
            return true
            #else
            return self?.userDataStore.debugMode ?? false
            #endif
        },
        testDeviceDescriptionProvider: { [weak self] in
            self?.userDefaults.string(forKey: PushRegistrationManager.testDeviceDescriptionDefaultsKey)
        },
        currentRegionIdentifierProvider: { [weak self] in self?.currentRegionIdentifier },
        errorReporter: { [weak self] error in
            self?.analytics?.reportError?(error)
        }
    )

    // Deliberately no Simulator carve-out: Simulators get real (sandbox) APNs tokens, so don't
    // re-add a `#if targetEnvironment(simulator)` guard here. See docs/push-notifications.md §6
    // for what a sandbox token does and doesn't receive.
    private func configurePushNotifications(launchOptions: [AnyHashable: Any]) {
        guard let pushServiceProvider = config.pushServiceProvider else { return }

        let pushService = PushService(serviceProvider: pushServiceProvider, delegate: self)
        self.pushService = pushService
        pushService.start(launchOptions: launchOptions)
    }

    /// A stop navigation (fired alarm push, `viewStop` deep link, or a donated
    /// stop `NSUserActivity`) received before the root view controller was
    /// installed, or before `currentRegion` had loaded. Drained once both exist.
    /// Internal so tests can assert the shortcut was stashed rather than dropped.
    var pendingStopID: StopID?
    /// Region the stashed stop belongs to. Nil for the URL-scheme path, which
    /// historically did not carry a region. When set, drain refuses to open the
    /// stop against a different region's API.
    var pendingStopRegionID: Int?
    /// The coordinate of an `onebusaway://rentals` link, held until a map can show
    /// it — the map's counterpart of `pendingStopID`. Whichever map surface is
    /// installed takes it with `claimPendingRentalsFocus()`, on appearing or on
    /// `.rentalsDeepLinkPending`, so a link that arrives on a cold launch or during
    /// onboarding is applied once the map exists and the region has loaded.
    var pendingRentalsCoordinate: CLLocationCoordinate2D?
    /// Lives here rather than on the map so it survives root reloads and sees every
    /// deep link, which arrive here before (or instead of) any map appearing.
    lazy var launchRouteGate = LaunchRouteGate(configValue: config.launchRouteID)
    private var presentDonationUIOnActive = false
    private var presentAddRegionAlertOnActive = false
    private var donationPromptID: String?

    public func pushService(_ pushService: PushService, receivedDonationPrompt id: String?) {
        guard let topViewController else {
            presentDonationUIOnActive = true
            donationPromptID = id
            return
        }

        presentDonationUI(topViewController, id: id)
    }

    private func presentDonationUI(_ presentingController: UIViewController, id: String?) {
        // `donationsEnabled` already folds in `obacoService != nil`, which is
        // exactly what `buildLearnMoreView`/`buildObservableDonationModel` need
        // to succeed — without this guard, a push arriving while donations are
        // disabled or Obaco is unavailable would both persist a false "shown"
        // state and crash on `buildLearnMoreView`'s internal `fatalError()`.
        guard donationsManager.donationsEnabled else { return }

        analytics?.reportEvent(pageURL: "app://localhost/donations", label: AnalyticsLabels.donationPushNotificationTapped, value: id)

        let learnMoreView = donationsManager.buildLearnMoreView(presentingController: presentingController, donationPushNotificationID: id)
        presentingController.presentDonationModal(learnMoreView, coordinator: promptCoordinator)
    }

    // MARK: - Alerts Store

    private var alertBulletin: AgencyAlertBulletin?

    @MainActor
    public func agencyAlertsUpdated() {
        #if DEBUG
        // UI tests run against the live network, so a real high-severity alert can
        // pop a modal bulletin over the UI mid-test. Tests that aren't about the
        // bulletin set this to keep their runs deterministic.
        if ProcessInfo.processInfo.environment["TEST_SUPPRESS_ALERT_BULLETINS"] == "1" {
            return
        }
        #endif

        guard
            let alert = alertsStore.recentUnreadHighSeverityAlerts.first,
            let app = self.delegate?.uiApplication
        else {
            return
        }

        alertsStore.markAlertRead(alert)

        alertBulletin = AgencyAlertBulletin(agencyAlert: alert, locale: locale)
        alertBulletin?.showMoreInformationHandler = { url in
            Task { @MainActor in
                if let topViewController = self.topViewController {
                    let safari = SFSafariViewController(url: url)
                    self.viewRouter.present(safari, from: topViewController, isModal: true)
                }
                else {
                    self.open(url, options: [:], completionHandler: nil)
                }
            }
        }
        alertBulletin?.show(in: app)
    }

    func agencyAlertsStore(_ store: AgencyAlertsStore, displayError error: Error) {
        Task {
            await self.displayError(error)
        }
    }

    // MARK: - UIApplication Hooks

    /// Provides access the topmost view controller in the app, if one exists.
    var topViewController: UIViewController? {
        delegate?.uiApplication?.keyWindowFromScene?.topViewController
    }

    @objc public func application(_ application: UIApplication, didFinishLaunching options: [AnyHashable: Any]) {
        application.shortcutItems = nil

        configurePushNotifications(launchOptions: options)
        reloadRootUserInterface()

        reportAnalyticsUserProperties()

        configureTipKit()
        if let provider = config.appShortcutsProvider {
            appShortcutParametersRefresher = AppShortcutParametersRefresher(provider: provider)
        }

        if userDataStore.walkingSpeedSource == .healthKit {
            Task { await walkingSpeedManager.refreshFromHealthKitIfPossible() }
        }

        // Matches the walking-speed refresh above: gated on the sync source alone, not
        // on whether Bike Mode is currently toggled on. The header's bike chip is always
        // shown regardless of mode, so a rider who synced once and later turned Bike Mode
        // off would otherwise keep a frozen cycling-speed ETA on every stop header forever.
        if userDataStore.bikeSpeedSource == .healthKit {
            Task { await bikeModeManager.refreshFromHealthKitIfPossible() }
        }
    }

    @MainActor @objc public func applicationDidBecomeActive(_ application: UIApplication) {
        // The user may have re-enabled Location Services while they were away,
        // which leaves `isLocationUseAuthorized` false until we probe for it.
        // The probe is asynchronous, so the gate below still sees the pre-probe
        // state — recovery is not this call's job. `LocationService` starts
        // updates itself when the probe clears the latch.
        locationService.retryIfLocationServicesDenied()

        if locationService.isLocationUseAuthorized {
            locationService.startUpdates()
        }

        // Re-arm proximity geofences and reap alerts that expired while the app was
        // away. Same reason the Live Activity cleanup below runs here: alerts age
        // out on a clock that keeps running with no process to notice, and the
        // regions standing for them outlive the process that armed them.
        proximityAlertManager.reconcileMonitoredRegions()

        // Clean up Live Activity subscriptions whose activities are gone. This has to run on an
        // app-lifecycle hook rather than in a view controller: an activity the user dismissed
        // while the app wasn't running has no observer to notice it, and the server will keep
        // pushing to it until the subscription is deleted. (The scene delegate calls this on
        // launch as well as on every foreground.)
        Task { await liveActivityRegistry.reconcile() }

        #if DEBUG
        // Lets UI tests exercise the modal alert bulletin deterministically,
        // without depending on a high-severity alert being live in the region.
        if ProcessInfo.processInfo.environment["TEST_INJECT_REGION_WIDE_ALERT"] == "1" {
            alertsStore.seedRegionWideAlertForTesting()
        }
        #endif

        alertsStore.checkForUpdates()

        // Re-register the push token with OBACloud so the server's inactivity prune never
        // drops this device, and so locale changes propagate. The manager dedupes, so this
        // only hits the network when something changed or the last POST is older than
        // PushRegistrationManager.refreshInterval. Skipped in apps without a configured
        // push provider, where pushService is never set.
        if pushService != nil {
            Task { await pushRegistrationManager.refreshRegistration() }
        }

        drainPendingUIPresentations()

        consumePendingLiveActivityShortcut()

        if let region = regionsService.currentRegion, let analytics {
            analytics.updateServer?(region: region)
        }
    }

    /// Called by the app delegates after the real root view controller is installed.
    ///
    /// The root now installs asynchronously (onboarding evaluation awaits notification
    /// settings), so on a cold launch `applicationDidBecomeActive` can fire while
    /// `topViewController` is still nil — anything stashed for later presentation would
    /// otherwise wait for the next foreground cycle. This is the deterministic drain point.
    @MainActor @objc public func rootUserInterfaceDidLoad() {
        drainPendingUIPresentations()
        consumePendingLiveActivityShortcut()
    }

    /// True while the onboarding flow is installed as the window's root — deferred
    /// presentations should not navigate out from under it.
    @MainActor
    private var isOnboardingRoot: Bool {
        delegate?.uiApplication?.keyWindowFromScene?.rootViewController is OnboardingFlowController
    }

    /// Presents any UI that arrived before a root view controller existed (cold-launch
    /// stop navigations, donation prompts, add-region errors). Idempotent: each stash is
    /// cleared on successful presentation. Runs from both `rootUserInterfaceDidLoad()`
    /// (the deterministic post-root drain) and `applicationDidBecomeActive` (later
    /// foregrounds), and never fires while onboarding is the root.
    @MainActor
    private func drainPendingUIPresentations() {
        guard !isOnboardingRoot else { return }

        if let stopID = pendingStopID, topViewController != nil {
            if let neededRegion = pendingStopRegionID {
                // Region still loading: wait. Loaded but different: drop — do not
                // fetch this stop against the wrong region's API.
                guard let current = currentRegion?.regionIdentifier else { return }
                if current != neededRegion {
                    pendingStopID = nil
                    pendingStopRegionID = nil
                    return
                }
            }
            pendingStopID = nil
            pendingStopRegionID = nil
            // While a modal is on its way out, anything presented from it goes with
            // it, so stop here; the dismissal re-runs this drain for the rest.
            let dismissing = pushStopFromOutside(stopID) { [weak self] in
                self?.drainPendingUIPresentations()
            }
            if dismissing { return }
        }

        if pendingRentalsCoordinate != nil, topViewController != nil {
            showMapForPendingRentals()
        }

        if presentDonationUIOnActive, let topViewController {
            presentDonationUI(topViewController, id: donationPromptID)
            presentDonationUIOnActive = false
            donationPromptID = nil
        }

        if presentAddRegionAlertOnActive, let topViewController {
            // Show alert for nil addRegion data
            let alertController = UIAlertController(
                title: Strings.error,
                message: OBALoc("region_url.error_messsage", value: "The provided region URL is invalid or does not point to a functional OBA server.", comment: "Error message of Custom Region URL if it's invalid or does not point to a functional OBA server"),
                preferredStyle: .alert
            )
            alertController.addAction(UIAlertAction(title: Strings.ok, style: .default))
            topViewController.present(alertController, animated: true)
            presentAddRegionAlertOnActive = false
        }
    }

    /// A Track Bookmark Shortcut queued a Live Activity. Consume it here from
    /// `topViewController` rather than switching to the Bookmarks tab — that
    /// tab's stack may already have a stop page pushed, and
    /// `rootNavigateTo(.bookmarks)` does not pop it.
    @MainActor
    func consumePendingLiveActivityShortcut() {
        guard !isOnboardingRoot else { return }
        LiveActivityShortcutDrain.consume(application: self, presentingFrom: topViewController)
    }

    /// `openAppWhenRun` activates the app before `perform()` stores, so
    /// `applicationDidBecomeActive` / `rootUserInterfaceDidLoad` peek an empty
    /// queue. Observe the store notification (warm launch).
    private func observeShortcutLifecycle() {
        notificationCenter.addObserver(
            forName: .liveActivityShortcutRequestDidStore,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.consumePendingLiveActivityShortcut()
            }
        }

        // Open Stop has no queue to peek: its request arrives only as this
        // notification, and `queueOrOpenStop(_:)` stashes the stop if the UI or
        // region isn't ready yet.
        notificationCenter.addObserver(
            forName: .openStopRequested,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let destination = notification.userInfo?[OpenStopRequest.destinationUserInfoKey] as? AppLinksRouter.StopDestination else {
                Logger.warn("Open Stop request has no stop destination; nothing to open.")
                return
            }
            MainActor.assumeIsolated {
                self.queueOrOpenStop(destination)
            }
        }
    }

    @objc public func applicationWillResignActive(_ application: UIApplication) {
        // Unconditional: stopping is always safe, and gating it on authorization
        // would strand a manager we started before access was revoked.
        locationService.stopUpdates()
    }

    public var isIdleTimerDisabled: Bool {
        get {
            return (delegate?.isIdleTimerDisabled ?? false)
        }
        set {
            delegate?.isIdleTimerDisabled = newValue
        }
    }

    public var isRegisteredForRemoteNotifications: Bool {
        delegate?.isRegisteredForRemoteNotifications ?? false
    }

    /// Provides access to the client app's main `Bundle`, from which you can
    /// access `Info.plist` data, among other things.
    public var applicationBundle: Bundle {
        return Bundle.main
    }

    /// Proxies `UIApplication.canOpenURL()`
    /// - Parameter url: The URL that we are checking can be opened.
    public func canOpenURL(_ url: URL) -> Bool {
        return delegate?.canOpenURL(url) ?? false
    }

    /// Proxies the equivalent method on `UIApplication`
    @objc func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any], completionHandler completion: ((Bool) -> Void)?) {
        delegate?.open(url, options: options, completionHandler: completion)
    }

    /// Proxies the delegate method.
    var credits: [String: String] {
        delegate?.credits ?? [:]
    }

    /// Opens `destination` now, or stashes it until the root UI and matching
    /// region exist. Does not fetch this stop against a different region's API.
    func queueOrOpenStop(_ destination: AppLinksRouter.StopDestination) {
        if let current = currentRegion?.regionIdentifier, current != destination.regionID {
            // Dropped on purpose — fetching this stop against another region's API
            // would return the wrong stop or nothing — but say so. This is the end
            // of the line for something the rider actually tapped, and the
            // no-region branch that defers instead already logs its reasoning.
            Logger.warn("Stop \(destination.stopID) belongs to region \(destination.regionID) but region \(current) is selected; dropping the tap.")
            Task { @MainActor in
                await self.displayError(UnstructuredError(OBALoc(
                    "application.stop_in_other_region",
                    value: "This stop is in a different region than the one you're using, so it can't be opened.",
                    comment: "Shown when the rider taps a link or notification for a stop that belongs to a transit region other than the currently selected one."
                )))
            }
            return
        }

        launchRouteGate.suppress()

        // Not while onboarding is the root: there is no API service to load the
        // stop with yet, and the page would be pushed over the region picker. The
        // drain picks the stash up once onboarding finishes.
        if topViewController != nil, !isOnboardingRoot, currentRegion?.regionIdentifier == destination.regionID {
            pushStopFromOutside(destination.stopID)
            return
        }

        pendingStopID = destination.stopID
        pendingStopRegionID = destination.regionID
    }

    @objc public func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard let appLinksRouter = appLinksRouter else {
            return false
        }

        let handled = appLinksRouter.route(userActivity: userActivity)
        if handled {
            launchRouteGate.suppress()
        }
        return handled
    }

    @MainActor
    @objc public func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard let scheme = Bundle.main.extensionURLScheme else {
            return false
        }

        guard let urlType = URLSchemeRouter(scheme: scheme).decodeURLType(from: url) else {
            return false
        }

        launchRouteGate.suppress()

        switch urlType {
        case .viewStop(let stopData):
            // Shares the stash, region check, and onboarding guard every other
            // stop entry point uses, rather than navigating against whichever
            // region happens to be selected.
            queueOrOpenStop(AppLinksRouter.StopDestination(stopID: stopData.stopID, regionID: stopData.regionID))
            return true
        case .viewRentals(let coordinate):
            pendingRentalsCoordinate = coordinate
            // UI not ready yet (cold launch) or onboarding up: the drain applies it.
            if topViewController != nil, !isOnboardingRoot {
                showMapForPendingRentals()
            }
            return true
        case .addRegion(let regionData):
            viewRouter.rootNavigateTo(page: .map)
            Task { @MainActor in
                do {
                    guard let regionData else {
                        presentAddRegionAlertOnActive = true
                        return
                    }

                    try await addCustomRegion(from: regionData)
                } catch {
                    presentAddRegionAlertOnActive = true
                    return
                }
            }
            return true
        }
    }

    override public func apiServicesRefreshed() {
        super.apiServicesRefreshed()
        donationsManager.obacoService = obacoService
    }

    // MARK: - Regions Management

    public func regionsService(_ service: RegionsService, changedAutomaticRegionSelection value: Bool) {
        let label = value ? AnalyticsLabels.setRegionAutomatically : AnalyticsLabels.setRegionManually
        analytics?.reportEvent(pageURL: "app://localhost/regions", label: label, value: nil)
    }

    public override func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        super.regionsService(service, updatedRegion: region)

        if let analytics {
            analytics.updateServer?(region: region)

            analytics.reportSetRegion(region.name)

            if !regionsService.automaticallySelectRegion {
                analytics.reportEvent(pageURL: "app://localhost/regions", label: AnalyticsLabels.manuallySelectedRegionChanged, value: region.name)
            }
        }

        // By the time updatedRegion fires, willUpdateToRegion has already rebuilt
        // obacoService for the new region, so this registers the token there.
        Task { await pushRegistrationManager.registerIfNeeded() }

        // A donated stop shortcut that arrived before `currentRegion` was set
        // is sitting in `pendingStopID`. Drain now that we know which region we are in.
        drainPendingUIPresentations()

        // Region change does not post `.bookmarksDidChange`, so Shortcuts
        // would keep offering the previous region's trip bookmarks.
        appShortcutParametersRefresher?.refresh()
    }

    public func regionsService(_ service: RegionsService, displayError error: Error) {
        Task {
            await displayError(error)
        }
    }

    // MARK: - Analytics

    public private(set) var analytics: Analytics?

    private func reportAnalyticsUserProperties() {
        let val = UIAccessibility.isVoiceOverRunning ? "YES" : "NO"
        analytics?.setUserProperty(key: "accessibility", value: val)
    }

    // MARK: - Error Visualization

    /// Classifies and displays an error to the end user.
    ///
    /// Shows a non-modal toast with a Details button rather than a modal card
    /// (#1582). Bursts of the same failure collapse into one toast; see
    /// `ErrorPresenter.shouldPresent(_:current:isShowingDetails:)`.
    @MainActor
    public override func displayError(_ error: Error) async {
        let report = ErrorReport(
            error: error,
            regionName: currentRegionName,
            isCellularDataRestricted: isCellularDataRestricted,
            systemVersion: Self.systemVersion,
            deviceModel: Self.deviceModel
        )
        // `report.summary` rather than `error.localizedDescription`: a 404's
        // description carries the full request URL, API key included.
        Logger.error("Error [\(report.reference)]: \(report.errorCode) \(report.requestURL?.absoluteString ?? "") \(report.summary)")

        analytics?.reportError?(error)

        guard let scene = delegate?.uiApplication?.errorToastTargetScene else {
            Logger.error("Error [\(report.reference)] not shown: no foreground window scene.")
            return
        }
        errorPresenter.present(report, in: scene)
    }

    private let errorPresenter = ErrorPresenter()

    // Fixed for the life of the process; `modelName` reflects over `uname`.
    private static let systemVersion = UIDevice.current.systemVersion
    private static let deviceModel = UIDevice.current.modelName

    // MARK: - Feature Availability

    /// Documents availability of features in whitelabel clients, so that features like alarms, weather, and trip status can be hidden or shown.
    ///
    /// `.off` means that a feature is simply unavailable in this app.
    /// `.notRunning` means that a feature is available, but not fully configured. This might be due to a race condition, for instance, and the caller should assume that the feature may be available in the future.
    /// `.running` means that the feature is ready to use.
    public lazy var features = FeatureAvailability(config: self.config, application: self)
}
