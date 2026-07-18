//
//  Application.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Combine
import CoreTelephony
import Hyperconnectivity
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
        analytics: analytics
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

    @objc lazy var userActivityBuilder = UserActivityBuilder(application: self)

    /// Handles all deep-linking into the app.
    @objc public private(set) lazy var appLinksRouter: AppLinksRouter? = makeAppLinksRouter()

    private func makeAppLinksRouter() -> AppLinksRouter? {
        let router = AppLinksRouter(application: self)

        router?.showStopHandler = { [weak self] stop in
            guard
                let self = self,
                let topVC = self.topViewController
            else { return }

            Task { @MainActor in
                self.viewRouter.navigateTo(stop: stop, from: topVC)
            }
        }

        router?.showArrivalDepartureDeepLink = { [weak self] deepLink in
            guard let self, let apiService = self.apiService else {
                return
            }

            Task(priority: .userInitiated) { @MainActor in
                ProgressHUD.show()

                do {
                    let arrDep = try await apiService.getTripArrivalDepartureAtStop(stopID: deepLink.stopID, tripID: deepLink.tripID, serviceDate: deepLink.serviceDate, vehicleID: deepLink.vehicleID, stopSequence: deepLink.stopSequence).entry

                    await MainActor.run {
                        if let topViewController = self.topViewController {
                            self.viewRouter.navigateTo(arrivalDeparture: arrDep, from: topViewController)
                        }
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

    // MARK: - Init

    /// Creates a new `Application` object.
    /// - Parameter config: A configuration object that determines the characteristics of this app.
    @objc public init(config: AppConfig) {
        self.config = config

        analytics = config.analytics

        super.init(config: config)

        configureAppearanceProxies()
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
    /// - Note: This method always returns `false` when running on a device. It will only ever return `true` on the Simulator.
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

    // MARK: - Reachability

    private var reachabilityBulletin: ReachabilityBulletin?

    private var hyperconnectivityCancellable: AnyCancellable?

    /// Long-lived instance so `restrictedState` has time to resolve from `.unknown`.
    private let cellularData = CTCellularData()

    /// Whether the user has disabled cellular data for this app in iOS Settings.
    var isCellularDataRestricted: Bool {
        return cellularData.restrictedState == .restricted
    }

    /// This may be called repeatedly as the app goes in and out of the foreground.
    private func configureConnectivity() {
        hyperconnectivityCancellable?.cancel()

        hyperconnectivityCancellable = Hyperconnectivity.Publisher()
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
            .sink(receiveValue: { [weak self] result in
                guard let self = self else { return }
                // `.receive(on: DispatchQueue.main)` above is what makes
                // `assumeIsolated` safe here — bulletin presentation is
                // `@MainActor`. Don't remove the `.receive(on:)` upstream;
                // doing so would silently turn this into a crash-on-mismatch.
                MainActor.assumeIsolated {
                    if result.isConnected {
                        self.reachabilityBulletin?.dismiss()
                        return
                    }

                    guard let app = self.delegate?.uiApplication else { return }

                    if self.reachabilityBulletin == nil {
                        self.reachabilityBulletin = ReachabilityBulletin()
                    }

                    self.reachabilityBulletin?.showStatus(result, in: app, isCellularDataRestricted: self.isCellularDataRestricted)
                }
            })
    }

    // MARK: - Push Notifications

    /// An optional property that contains this app's configured push notifications service.
    public private(set) var pushService: PushService?

    private func configurePushNotifications(launchOptions: [AnyHashable: Any]) {
        guard let pushServiceProvider = config.pushServiceProvider else { return }

        #if targetEnvironment(simulator)
            Logger.warn("Push notifications don't work on the Simulator. Run this app on a device instead!")
            return
        #else
            self.pushService = PushService(serviceProvider: pushServiceProvider, delegate: self)
            self.pushService?.start(launchOptions: launchOptions)
        #endif
    }

    public func pushServicePresentingController(_ pushService: PushService) -> UIViewController? {
        topViewController
    }

    public func pushService(_ pushService: PushService, received pushBody: AlarmPushBody) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Remove the fired alarm from the local store and let open stop pages
            // update their alarm index via the notification.
            self.deleteMatchingAlarm(for: pushBody)
            NotificationCenter.default.post(name: .alarmFired, object: nil)

            guard let topViewController = self.topViewController else {
                // UI not ready yet (cold launch). Navigate once the scene activates.
                self.pendingStopID = pushBody.stopID
                return
            }
            self.viewRouter.navigateTo(stopID: pushBody.stopID, from: topViewController)
        }
    }

    /// Deletes the stored alarm whose deep-link identity matches `pushBody`, so the stop
    /// page reflects the fired state without waiting for the next full refresh.
    @MainActor
    private func deleteMatchingAlarm(for pushBody: AlarmPushBody) {
        for alarm in userDataStore.alarms {
            guard let deepLink = alarm.deepLink else { continue }
            guard deepLink.stopID == pushBody.stopID,
                  deepLink.tripID == pushBody.tripID,
                  deepLink.stopSequence == pushBody.stopSequence,
                  abs(deepLink.serviceDate.timeIntervalSince(pushBody.serviceDate)) < 60
            else { continue }
            userDataStore.delete(alarm: alarm)
            return
        }
    }

    /// A stop navigation (fired alarm push or `viewStop` deep link) received before the
    /// root view controller was installed (cold launch). Drained on activation once a
    /// root view controller exists.
    private var pendingStopID: StopID?
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
        analytics?.reportEvent(pageURL: "app://localhost/donations", label: AnalyticsLabels.donationPushNotificationTapped, value: id)

        let learnMoreView = donationsManager.buildLearnMoreView(presentingController: presentingController, donationPushNotificationID: id)
        presentingController.present(UIHostingController(rootView: learnMoreView), animated: true)
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
    private var topViewController: UIViewController? {
        delegate?.uiApplication?.keyWindowFromScene?.topViewController
    }

    @objc public func application(_ application: UIApplication, didFinishLaunching options: [AnyHashable: Any]) {
        application.shortcutItems = nil

        configurePushNotifications(launchOptions: options)
        reloadRootUserInterface()

        reportAnalyticsUserProperties()

        configureTipKit()

        if userDataStore.walkingSpeedSource == .healthKit {
            Task { await walkingSpeedManager.refreshFromHealthKitIfPossible() }
        }
    }

    @MainActor @objc public func applicationDidBecomeActive(_ application: UIApplication) {
        if locationService.isLocationUseAuthorized {
            locationService.startUpdates()
        }

        configureConnectivity()

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

        drainPendingUIPresentations()

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

        if let stopID = pendingStopID, let topViewController {
            viewRouter.navigateTo(stopID: stopID, from: topViewController)
            pendingStopID = nil
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

    @objc public func applicationWillResignActive(_ application: UIApplication) {
        if locationService.isLocationUseAuthorized {
            locationService.stopUpdates()
        }

        hyperconnectivityCancellable?.cancel()
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

    @objc public func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard let appLinksRouter = appLinksRouter else {
            return false
        }

        return appLinksRouter.route(userActivity: userActivity)
    }

    @MainActor
    @objc public func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard let scheme = Bundle.main.extensionURLScheme else {
            return false
        }

        let router = URLSchemeRouter(scheme: scheme)

        guard let urlType = router.decodeURLType(from: url) else {
            return false
        }

        switch urlType {
        case .viewStop(let stopData):
            guard let topViewController = self.topViewController else {
                // UI not ready yet (cold launch). Navigate once the scene activates.
                pendingStopID = stopData.stopID
                return true
            }
            viewRouter.navigateTo(stopID: stopData.stopID, from: topViewController)
            return true
        case .addRegion(let regionData):
            viewRouter.rootNavigateTo(page: .map)
            Task { @MainActor in
                do {
                    guard let regionData else {
                        presentAddRegionAlertOnActive = true
                        return
                    }

                    guard let regionCoordinate = try await self.apiService?.getAgenciesWithCoverage().list.first?.region else {
                        return
                    }

                    // Adjustments for coordinate span
                    var adjustedRegionCoordinate = regionCoordinate
                    adjustedRegionCoordinate.span.latitudeDelta = 2
                    adjustedRegionCoordinate.span.longitudeDelta = 2

                    // Create region provider
                    let regionProvider = RegionPickerCoordinator(regionsService: self.regionsService, userDataStore: self.userDataStore)

                    // Construct Region from URL data
                    let currentRegion = Region(name: regionData.name, OBABaseURL: regionData.obaURL, coordinateRegion: adjustedRegionCoordinate, contactEmail: "example@example.com", openTripPlannerURL: regionData.otpURL)

                    // Add and set current region
                    try await regionProvider.add(customRegion: currentRegion)
                    try await regionProvider.setCurrentRegion(to: currentRegion)
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

    // MARK: - Appearance and Themes

    /// Sets default styles for several UIAppearance proxies in order to customize the app's look and feel
    ///
    /// To override the values that are set in here, either customize the theme that this object is
    /// configured with at launch or simply don't call this method and set up your own `UIAppearance`
    /// proxies instead.
    private func configureAppearanceProxies() {
        for t in [UIWindow.self, UINavigationBar.self, UISearchBar.self, UISegmentedControl.self, UITabBar.self, UITextField.self, UIButton.self] {
            t.appearance().tintColor = ThemeColors.shared.brand
        }

        UISwitch.appearance().onTintColor = ThemeColors.shared.brand

        StopArrivalView.appearance().notificationCenter = notificationCenter

        MKMarkerAnnotationView.appearance().markerTintColor = ThemeColors.shared.brand

        UIBarButtonItem.appearance().setTitleTextAttributes([.foregroundColor: ThemeColors.shared.brand], for: .normal)
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
    @MainActor
    public override func displayError(_ error: Error) async {
        let classified = ErrorClassifier.classify(error, regionName: currentRegionName, isCellularDataRestricted: isCellularDataRestricted)
        Logger.error("Error: \(classified.localizedDescription)")

        analytics?.reportError?(error)

        guard let uiApp = delegate?.uiApplication else { return }
        let bulletin = ErrorBulletin(application: self, classifiedError: classified)
        bulletin.show(in: uiApp)
        self.errorBulletin = bulletin
    }

    private var errorBulletin: ErrorBulletin?

    // MARK: - Feature Availability

    /// Models feature availability state in the app.
    ///
    /// Some applications might have support for features, like push notifications, that other white label versions of the app might lack.
    /// `FeatureStatus` and `FeatureAvailability` describe whether those features are unavailable, not running, or available for use.
    public enum FeatureStatus {

        /// This feature is not available in this app.
        case off

        /// This feature is available, but is not fully configured for use.
        ///
        /// This might be due to a race condition, for instance, and the caller should assume that the feature may be available in the future.
        case notRunning

        /// This feature is available for use.
        case running
    }

    /// Describes feature availability state in the app.
    ///
    /// Some applications might have support for features, like push notifications, that other white label versions of the app might lack.
    /// `FeatureStatus` and `FeatureAvailability` describe whether those features are unavailable, not running, or available for use.
    public struct FeatureAvailability {
        private let config: AppConfig
        private weak var application: Application?

        init(config: AppConfig, application: Application) {
            self.config = config
            self.application = application
        }

        /// Feature status of the Obaco service.
        public var obaco: FeatureStatus {
            switch (application?.regionsService.currentRegion?.sidecarBaseURL, application?.obacoService) {
            case (nil, nil): return .off
            case (_, nil): return .notRunning
            default: return .running
            }
        }

        /// Feature status of push notifications.
        public var push: FeatureStatus {
            switch (config.pushServiceProvider, application?.pushService) {
            case (nil, nil): return .off
            case (_, nil): return .notRunning
            default: return .running
            }
        }

        /// Feature status of Deep Linking.
        public var deepLinking: FeatureStatus {
            switch (application?.regionsService.currentRegion?.sidecarBaseURL, application?.appLinksRouter) {
            case (nil, nil): return .off
            case (_, nil): return .notRunning
            default: return .running
            }
        }

        /// Feature status of OTP trip planning.
        public var tripPlanning: FeatureStatus {
            guard
                let region = application?.regionsService.currentRegion,
                region.supportsOTP
            else {
                return .off
            }

            return .running
        }
    }

    /// Documents availability of features in whitelabel clients, so that features like alarms, weather, and trip status can be hidden or shown.
    ///
    /// `.off` means that a feature is simply unavailable in this app.
    /// `.notRunning` means that a feature is available, but not fully configured. This might be due to a race condition, for instance, and the caller should assume that the feature may be available in the future.
    /// `.running` means that the feature is ready to use.
    public lazy var features = FeatureAvailability(config: self.config, application: self)
}
