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

@objc(OBAApplication)
public class Application: CoreApplication, PushServiceDelegate {

    // MARK: - Private Properties

    /// App configuration parameters: API keys, region server, user UUID, and other
    /// configuration values.
    private let config: AppConfig

    // MARK: - Public Properties

    /// Responsible for figuring out how to navigate between view controllers.
    @objc public lazy var viewRouter = ViewRouter(application: self)

    /// Responsible for creating stop 'badges' for the map.
    public lazy var stopIconFactory = StopIconFactory(iconSize: ThemeMetrics.defaultMapAnnotationSize)

    @objc public private(set) lazy var mapRegionManager = MapRegionManager(application: self)

    @objc public private(set) lazy var searchManager = SearchManager(application: self)

    @objc public private(set) lazy var userActivityBuilder = UserActivityBuilder(application: self)

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
                let modelService = self.restAPIModelService
            else { return }

            SVProgressHUD.show()

            let op = modelService.getTripArrivalDepartureAtStop(stopID: deepLink.stopID, tripID: deepLink.tripID, serviceDate: deepLink.serviceDate, vehicleID: deepLink.vehicleID, stopSequence: deepLink.stopSequence)
            op.then { [weak self] in
                guard
                    let self = self,
                    let topVC = self.topViewController,
                    let arrDep = op.arrivalDeparture
                else {
                    return
                }

                SVProgressHUD.dismiss()

                self.viewRouter.navigateTo(arrivalDeparture: arrDep, from: topVC)
            }
        }

        return router
    }()

    @objc public weak var delegate: ApplicationDelegate?

    @objc public let reachability = Reachability()

    private var locationPermissionBulletin: LocationPermissionBulletin?

    // MARK: - Init

    @objc public init(config: AppConfig) {
        self.config = config

        analytics = config.analytics

        super.init(config: config)

        configureLogging()

        configureAppearanceProxies()

        configureConnectivity()
    }

    // MARK: - App State Management

    /// True when the app should show an interstitial location service permission
    /// request user interface. Meant to be called on app launch to determine
    /// which piece of UI should be shown initially.
    @objc public var showPermissionPromptUI: Bool {
        return locationService.canRequestAuthorization && locationService.canPromptUserForPermission
    }

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
    public let connectivity = Connectivity()

    private var reachabilityBulletin: ReachabilityBulletin?

    /// This method must only be called once when the `Application` object is first created.
    private func configureConnectivity() {
        connectivity.framework = .network

        connectivity.whenConnected = { [weak self] connectivity in
            self?.reachabilityBulletin?.dismiss()
        }

        connectivity.whenDisconnected = { [weak self] connectivity in
            guard let app = self?.delegate?.uiApplication else { return }

            if self?.reachabilityBulletin == nil {
                self?.reachabilityBulletin = ReachabilityBulletin()
            }

            self?.reachabilityBulletin?.showStatus(connectivity.status, in: app)
        }
    }

    // MARK: - Push Notifications

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
        guard let modelService = restAPIModelService else {
            return
        }

        let op = modelService.getTripArrivalDepartureAtStop(stopID: pushBody.stopID, tripID: pushBody.tripID, serviceDate: pushBody.serviceDate, vehicleID: pushBody.vehicleID, stopSequence: pushBody.stopSequence)
        op.then { [weak self] in
            guard
                let self = self,
                let topController = self.delegate?.uiApplication?.keyWindow?.topViewController,
                let arrivalDeparture = op.arrivalDeparture
            else { return }

            let tripController = TripViewController(application: self, arrivalDeparture: arrivalDeparture)
            self.viewRouter.navigate(to: tripController, from: topController)
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
        configurePushNotifications(launchOptions: options)
        reloadRootUserInterface()

        if showPermissionPromptUI {
            self.locationPermissionBulletin = LocationPermissionBulletin(locationService: locationService, regionsService: regionsService)
            self.locationPermissionBulletin?.show(in: application)
        }
        else if regionsService.currentRegion == nil {
            regionPickerBulletin = RegionPickerBulletin(regionsService: regionsService)
            regionPickerBulletin?.show(in: application)
        }

        reportAnalyticsUserProperties()
    }

    @objc public func applicationDidBecomeActive(_ application: UIApplication) {
        if locationService.isLocationUseAuthorized {
            locationService.startUpdates()
        }

        connectivity.startNotifier()
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
    }

    // MARK: - Appearance and Themes

    // swiftlint:disable function_body_length

    /// Sets default styles for several UIAppearance proxies in order to customize the app's look and feel
    ///
    /// To override the values that are set in here, either customize the theme that this object is
    /// configured with at launch or simply don't call this method and set up your own `UIAppearance`
    /// proxies instead.
    private func configureAppearanceProxies() {
        let tintColor = ThemeColors.shared.brand
        let tintColorTypes = [UIWindow.self, UINavigationBar.self, UISearchBar.self, UISegmentedControl.self, UITabBar.self, UITextField.self, UIButton.self]

        for t in tintColorTypes {
            t.appearance().tintColor = tintColor
        }

        BorderedButton.appearance().setTitleColor(ThemeColors.shared.lightText, for: .normal)
        BorderedButton.appearance().tintColor = ThemeColors.shared.brand

        EmptyDataSetView.appearance().bodyLabelFont = UIFont.preferredFont(forTextStyle: .body)
        EmptyDataSetView.appearance().textColor = ThemeColors.shared.secondaryLabel
        EmptyDataSetView.appearance().titleLabelFont = UIFont.preferredFont(forTextStyle: .title1).bold

        FloatingPanelTitleView.appearance().titleFont = UIFont.preferredFont(forTextStyle: .title2).bold
        FloatingPanelTitleView.appearance().subtitleFont = UIFont.preferredFont(forTextStyle: .body)

        HighlightChangeLabel.appearance().highlightedBackgroundColor = ThemeColors.shared.propertyChanged

        IndeterminateProgressView.appearance().progressColor = ThemeColors.shared.brand

        StackedTitleView.appearance().subtitleFont = UIFont.preferredFont(forTextStyle: .footnote)
        StackedTitleView.appearance().titleFont = UIFont.preferredFont(forTextStyle: .footnote).bold

        StatusOverlayView.appearance().innerPadding = ThemeMetrics.padding
        StatusOverlayView.appearance().textColor = ThemeColors.shared.lightText

        MinimalStopAnnotationView.appearance().annotationSize = 10.0
        MinimalStopAnnotationView.appearance().fillColor = .white
        MinimalStopAnnotationView.appearance().strokeColor = .gray
        MinimalStopAnnotationView.appearance().highlightedStrokeColor = .blue

        StopAnnotationView.appearance().annotationSize = ThemeMetrics.defaultMapAnnotationSize
        StopAnnotationView.appearance().bookmarkedStrokeColor = ThemeColors.shared.brand
        StopAnnotationView.appearance().fillColor = UIColor.white
        StopAnnotationView.appearance().mapTextColor = ThemeColors.shared.mapText
        StopAnnotationView.appearance().showsCallout = true
        StopAnnotationView.appearance().strokeColor = ThemeColors.shared.stopAnnotationStrokeColor

        PulsingVehicleAnnotationView.appearance().tintColor = .white
        PulsingVehicleAnnotationView.appearance().realTimeAnnotationColor = ThemeColors.shared.brand
        PulsingVehicleAnnotationView.appearance().scheduledAnnotationColor = ThemeColors.shared.gray

        SubtitleTableCell.appearance().subtitleFont = UIFont.preferredFont(forTextStyle: .footnote)

        TableHeaderView.appearance().font = UIFont.preferredFont(forTextStyle: .footnote)
        TableHeaderView.appearance().textColor = ThemeColors.shared.secondaryLabel

        TableSectionHeaderView.appearance().backgroundColor = ThemeColors.shared.secondaryBackgroundColor

        TripSegmentView.appearance().imageColor = ThemeColors.shared.brand
        TripSegmentView.appearance().lineColor = ThemeColors.shared.gray

        WalkTimeView.appearance().font = UIFont.preferredFont(forTextStyle: .footnote)
        WalkTimeView.appearance().backgroundBarColor = ThemeColors.shared.brand
        WalkTimeView.appearance().textColor = ThemeColors.shared.lightText

        UIBarButtonItem.appearance().setTitleTextAttributes([.foregroundColor: tintColor], for: .normal)

        // See: https://github.com/Instagram/IGListKit/blob/master/Guides/Working%20with%20UICollectionView.md
        UICollectionView.appearance().isPrefetchingEnabled = false
    }
    // swiftlint:enable function_body_length

    // MARK: - Regions Management

    private var regionPickerBulletin: RegionPickerBulletin?

    public func regionsServiceUnableToSelectRegion(_ service: RegionsService) {
        guard let app = delegate?.uiApplication else { return }

        self.regionPickerBulletin = RegionPickerBulletin(regionsService: regionsService)
        self.regionPickerBulletin?.show(in: app)
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
