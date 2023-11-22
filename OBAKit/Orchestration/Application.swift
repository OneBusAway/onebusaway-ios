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
import Hyperconnectivity
import CoreLocation
import OBAKitCore
import SafariServices
import MapKit
import SwiftUI
import StripeApplePay

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

    @objc lazy var userActivityBuilder = UserActivityBuilder(application: self)

    /// Handles all deep-linking into the app.
    @objc public private(set) lazy var appLinksRouter: AppLinksRouter? = {
        let router = AppLinksRouter(baseURL: applicationBundle.deepLinkServerBaseAddress, application: self)
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

            Task(priority: .userInitiated) {
                await ProgressHUD.show()

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

                await ProgressHUD.dismiss()
            }
        }

        return router
    }()

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

    /// This may be called repeatedly as the app goes in and out of the foreground.
    private func configureConnectivity() {
        hyperconnectivityCancellable?.cancel()

        hyperconnectivityCancellable = Hyperconnectivity.Publisher()
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
            .sink(receiveValue: { [weak self] result in
                guard let self = self else { return }
                if result.isConnected {
                    self.reachabilityBulletin?.dismiss()
                }
                else {
                    guard let app = self.delegate?.uiApplication else { return }

                    if self.reachabilityBulletin == nil {
                        self.reachabilityBulletin = ReachabilityBulletin()
                    }

                    self.reachabilityBulletin?.showStatus(result, in: app)
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
        guard let apiService = apiService else { return }

        Task(priority: .userInitiated) { [weak self] in
            do {
                let arrivalDeparture = try await apiService.getTripArrivalDepartureAtStop(stopID: pushBody.stopID, tripID: pushBody.tripID, serviceDate: pushBody.serviceDate, vehicleID: pushBody.vehicleID, stopSequence: pushBody.stopSequence).entry

                if let self, let topViewController = self.topViewController {
                    await MainActor.run {
                        let tripController = TripViewController(application: self, arrivalDeparture: arrivalDeparture)
                        self.viewRouter.navigate(to: tripController, from: topViewController)
                    }
                }
            } catch {
                await self?.displayError(error)
            }
        }
    }

    private var presentDonationUIOnActive = false
    private var donationPromptID: String? = nil

    public func pushService(_ pushService: PushService, receivedDonationPrompt id: String?) {
        guard let topViewController else {
            presentDonationUIOnActive = true
            donationPromptID = id
            return
        }

        presentDonationUI(topViewController, id: id)
    }

    private func presentDonationUI(_ presentingController: UIViewController, id: String?) {
        analytics?.reportEvent?(.userAction, label: AnalyticsLabels.donationPushNotificationTapped, value: id)

        let learnMoreView = donationsManager.buildLearnMoreView(presentingController: presentingController, donationPushNotificationID: id)
        presentingController.present(UIHostingController(rootView: learnMoreView), animated: true)
    }

    // MARK: - Alerts Store

    private var alertBulletin: AgencyAlertBulletin?

    public func agencyAlertsUpdated() {
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
        donationsManager.refreshStripePublishableKey()

        application.shortcutItems = nil

        configurePushNotifications(launchOptions: options)
        reloadRootUserInterface()

        reportAnalyticsUserProperties()
    }

    @objc public func applicationDidBecomeActive(_ application: UIApplication) {
        if locationService.isLocationUseAuthorized {
            locationService.startUpdates()
        }

        configureConnectivity()
        alertsStore.checkForUpdates()

        if presentDonationUIOnActive, let topViewController {
            presentDonationUI(topViewController, id: donationPromptID)
            presentDonationUIOnActive = false
            donationPromptID = nil
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
        if StripeAPI.handleURLCallback(with: url) {
            return true
        }

        guard let scheme = Bundle.main.extensionURLScheme else {
            return false
        }

        let router = URLSchemeRouter(scheme: scheme)
        guard
            let stopData = router.decode(url: url),
            let topViewController = topViewController
        else {
            return false
        }

        viewRouter.navigateTo(stopID: stopData.stopID, from: topViewController)
        return true
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
        analytics?.reportEvent?(.userAction, label: label, value: nil)
    }

    public override func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        super.regionsService(service, updatedRegion: region)

        analytics?.reportSetRegion?(region.name)

        if !regionsService.automaticallySelectRegion {
            analytics?.reportEvent?(.userAction, label: AnalyticsLabels.manuallySelectedRegionChanged, value: region.name)
        }
    }

    public func regionsService(_ service: RegionsService, displayError error: Error) {
        Task {
            await displayError(error)
        }
    }

    // MARK: - Analytics

    @objc public private(set) var analytics: Analytics?

    private func reportAnalyticsUserProperties() {
        let val = UIAccessibility.isVoiceOverRunning ? "YES" : "NO"
        analytics?.setUserProperty?(key: "accessibility", value: val)
    }

    // MARK: - Error Visualization

    /// Displays an error to the end user.
    ///
    /// Hopefully, the error object conforms to `LocalizedError` and provides an understandable, localized
    /// explanation to the user via `localizedDescription`.
    ///
    /// - Parameter error: The error to display.
    @MainActor
    public override func displayError(_ error: Error) async {
        await super.displayError(error)
        guard let uiApp = delegate?.uiApplication else { return }
        let bulletin = ErrorBulletin(application: self, message: error.localizedDescription)
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
            switch (config.obacoBaseURL, application?.obacoService) {
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
            switch (config.obacoBaseURL, application?.appLinksRouter) {
            case (nil, nil): return .off
            case (_, nil): return .notRunning
            default: return .running
            }
        }
    }

    /// Documents availability of features in whitelabel clients, so that features like alarms, weather, and trip status can be hidden or shown.
    ///
    /// `.off` means that a feature is simply unavailable in this app.
    /// `.notRunning` means that a feature is available, but not fully configured. This might be due to a race condition, for instance, and the caller should assume that the feature may be available in the future.
    /// `.running` means that the feature is ready to use.
    public lazy var features = FeatureAvailability(config: self.config, application: self)
}
