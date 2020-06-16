//
//  Application.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/15/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import Connectivity
import CoreLocation
import OBAKitCore
import CocoaLumberjackSwift
import SafariServices

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

    /// Responsible for figuring out how to navigate between view controllers.
    lazy var viewRouter = ViewRouter(application: self)

    /// Responsible for creating stop 'badges' for the map.
    lazy var stopIconFactory = StopIconFactory(iconSize: ThemeMetrics.defaultMapAnnotationSize)

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

            self.viewRouter.navigateTo(stop: stop, from: topVC)
        }

        router?.showArrivalDepartureDeepLink = { [weak self] deepLink in
            guard
                let self = self,
                let apiService = self.restAPIService
            else { return }

            SVProgressHUD.show()

            let op = apiService.getTripArrivalDepartureAtStop(stopID: deepLink.stopID, tripID: deepLink.tripID, serviceDate: deepLink.serviceDate, vehicleID: deepLink.vehicleID, stopSequence: deepLink.stopSequence)
            op.complete { [weak self] result in
                SVProgressHUD.dismiss()

                guard
                    let self = self,
                    let topVC = self.topViewController
                else { return }

                switch result {
                case .failure(let error):
                    print("TODO FIXME handle error! \(error)")
                case .success(let response):
                    self.viewRouter.navigateTo(arrivalDeparture: response.entry, from: topVC)
                }
            }
        }

        return router
    }()

    /// The application delegate object.
    @objc public weak var delegate: ApplicationDelegate?

    /// Reachability is responsible for determining if the user has a functioning Internet connection.
    @objc public let reachability = Reachability()

    // MARK: - Init

    /// Creates a new `Application` object.
    /// - Parameter config: A configuration object that determines the characteristics of this app.
    @objc public init(config: AppConfig) {
        self.config = config

        connectivity = config.connectivity
        analytics = config.analytics

        super.init(config: config)

        configureLogging()

        configureAppearanceProxies()

        configureConnectivity()
    }

    // MARK: - Onboarding

    private lazy var onboarder = Onboarder(locationService: locationService, regionsService: regionsService, dataMigrator: dataMigrator)

    /// Performs the full onboarding process: location permissions, region selection, and data migration.
    public func performOnboarding() {
        guard
            onboarder.onboardingRequired,
            let uiApp = self.delegate?.uiApplication
        else { return }

        onboarder.show(in: uiApp)
    }

    // MARK: - Onboarding/Data Migration

    /// When true, this means that the application's user defaults contain data that can be migrated into a modern format.
    public var hasDataToMigrate: Bool { dataMigrationBulletin.hasDataToMigrate }

    lazy var dataMigrationBulletin = DataMigrationBulletinManager(dataMigrator: dataMigrator)

    /// If data exists to migrate, this method will prompt the user about whether they wish to migrate data from an old format to the new format.
    public func performDataMigration() {
        guard
            hasDataToMigrate,
            let uiApp = self.delegate?.uiApplication
        else { return }

        dataMigrationBulletin.show(in: uiApp)
    }

    // MARK: - UI

    /// Requests that the delegate reloads the application user interface in
    /// response to major state changes, like permission changes or the selected
    /// region transitioning from nil -> not-nil.
    public func reloadRootUserInterface() {
        delegate?.applicationReloadRootInterface(self)
    }

    // MARK: - Logging

    private func configureLogging() {
        DDLog.add(DDOSLogger.sharedInstance, with: .info)

        let fileLogger: DDFileLogger = DDFileLogger()
        fileLogger.rollingFrequency = 60 * 60 * 24 // 24 hours
        fileLogger.logFileManager.maximumNumberOfLogFiles = 7 // 1 week.
        DDLog.add(fileLogger, with: .info)
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

    /// Provides information on the current status of the app's network connection
    ///
    /// In other words, it answers the following questions:
    /// 1. Is the network (WiFi or Cellular) currently working?
    /// 2. Is the server working?
    public let connectivity: ReachabilityProtocol

    private var reachabilityBulletin: ReachabilityBulletin?

    /// This method must only be called once when the `Application` object is first created.
    private func configureConnectivity() {
        connectivity.connected { [weak self] _ in
            guard let self = self else { return }
            self.reachabilityBulletin?.dismiss()
        }

        connectivity.disconnected { [weak self] reach in
            guard
                let self = self,
                let app = self.delegate?.uiApplication
            else { return }

            if self.reachabilityBulletin == nil {
                self.reachabilityBulletin = ReachabilityBulletin()
            }

            self.reachabilityBulletin?.showStatus(reach.status, in: app)
        }
    }

    // MARK: - Push Notifications

    /// An optional property that contains this app's configured push notifications service.
    public private(set) var pushService: PushService?

    private func configurePushNotifications(launchOptions: [AnyHashable: Any]) {
        guard let pushServiceProvider = config.pushServiceProvider else { return }

        #if targetEnvironment(simulator)
            DDLogWarn("Push notifications don't work on the Simulator. Run this app on a device instead!")
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
        guard let apiService = restAPIService else { return }

        let op = apiService.getTripArrivalDepartureAtStop(stopID: pushBody.stopID, tripID: pushBody.tripID, serviceDate: pushBody.serviceDate, vehicleID: pushBody.vehicleID, stopSequence: pushBody.stopSequence)
        op.complete { [weak self] result in
            guard
                let self = self,
                let topController = self.delegate?.uiApplication?.keyWindow?.topViewController
            else { return }

            switch result {
            case .failure(let error):
                print("TODO FIXME handle error! \(error)")
            case .success(let response):
                let tripController = TripViewController(application: self, arrivalDeparture: response.entry)
                self.viewRouter.navigate(to: tripController, from: topController)
            }
        }
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
            if let topViewController = self.topViewController {
                let safari = SFSafariViewController(url: url)
                self.viewRouter.present(safari, from: topViewController, isModal: true)
            }
            else {
                self.open(url, options: [:], completionHandler: nil)
            }
        }
        alertBulletin?.show(in: app)
    }

    // MARK: - UIApplication Hooks

    /// Provides access the topmost view controller in the app, if one exists.
    private var topViewController: UIViewController? {
        delegate?.uiApplication?.keyWindow?.topViewController
    }

    @objc public func application(_ application: UIApplication, didFinishLaunching options: [AnyHashable: Any]) {
        application.shortcutItems = nil

        configurePushNotifications(launchOptions: options)
        reloadRootUserInterface()

        performOnboarding()

        reportAnalyticsUserProperties()
    }

    @objc public func applicationDidBecomeActive(_ application: UIApplication) {
        if locationService.isLocationUseAuthorized {
            locationService.startUpdates()
        }

        connectivity.startNotifier(queue: .main)
        alertsStore.checkForUpdates()
    }

    @objc public func applicationWillResignActive(_ application: UIApplication) {
        if locationService.isLocationUseAuthorized {
            locationService.stopUpdates()
        }

        connectivity.stopNotifier()
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

    @objc public func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
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

        // See: https://github.com/Instagram/IGListKit/blob/master/Guides/Working%20with%20UICollectionView.md
        UICollectionView.appearance().isPrefetchingEnabled = false
    }

    // MARK: - Regions Management

    public func regionsServiceUnableToSelectRegion(_ service: RegionsService) {
        guard let app = delegate?.uiApplication else { return }

        onboarder.show(in: app)
    }

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

    // MARK: - Analytics

    @objc public private(set) var analytics: Analytics?

    private func reportAnalyticsUserProperties() {
        let val = UIAccessibility.isVoiceOverRunning ? "YES" : "NO"
        analytics?.setUserProperty?(key: "accessibility", value: val)
    }

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
