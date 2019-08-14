//
//  Application.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/15/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import CoreLocation

// MARK: - Protocols

@objc(OBAApplicationDelegate)
public protocol ApplicationDelegate {

    /// This method is called when the delegate should reload the `rootViewController`
    /// of the app's window. This is typically done in response to permissions changes.
    @objc func applicationReloadRootInterface(_ app: Application)

    /// This method is called when the application cannot automatically select a `Region`
    /// for the user. It provides a region picker that must be displayed to the user so
    /// that the user can pick a `Region`, thereby allowing the app to continue functioning.
    ///
    /// - Parameters:
    ///   - app: The application object.
    ///   - picker: The region picker view controller to display to the user.
    @objc func application(_ app: Application, displayRegionPicker picker: RegionPickerViewController)

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
public class Application: NSObject, RegionsServiceDelegate, LocationServiceDelegate {

    // MARK: - Private Properties

    /// App configuration parameters: API keys, region server, user UUID, and other
    /// configuration values.
    private let config: AppConfig

    // MARK: - Public Properties

    /// Shared user defaults
    @objc public let userDefaults: UserDefaults

    /// The data store for information like bookmarks, groups, and recent stops.
    @objc public let userDataStore: UserDataStore

    /// Commonly used formatters configured with the user's current, auto-updating locale and the app's theme colors.
    @objc public lazy var formatters = Formatters(locale: Locale.autoupdatingCurrent, themeColors: ThemeColors.shared)

    /// Provides access to the user's location and heading.
    @objc public let locationService: LocationService

    /// Responsible for figuring out how to navigate between view controllers.
    @objc public lazy var viewRouter = ViewRouter(application: self)

    /// Responsible for managing `Region`s and determining the correct `Region` for the user.
    @objc public let regionsService: RegionsService

    /// Helper property that returns `regionsService.currentRegion`.
    @objc public var currentRegion: Region? {
        return regionsService.currentRegion
    }

    /// Responsible for creating stop 'badges' for the map.
    public lazy var stopIconFactory = StopIconFactory(iconSize: ThemeMetrics.defaultMapAnnotationSize)

    /// Provides access to the OneBusAway REST API
    ///
    /// - Note: See [develop.onebusaway.org](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/index.html)
    ///         for more information on the REST API.
    @objc public private(set) var restAPIModelService: RESTAPIModelService?

    @objc public private(set) var obacoService: ObacoModelService?

    private var obacoNetworkQueue = OperationQueue()

    @objc public private(set) lazy var mapRegionManager = MapRegionManager(application: self)

    @objc public private(set) lazy var searchManager = SearchManager(application: self)

    @objc public private(set) var theme: Theme

    @objc public private(set) lazy var userActivityBuilder = UserActivityBuilder(application: self)

    @objc public private(set) lazy var deepLinkRouter = DeepLinkRouter(baseURL: applicationBundle.deepLinkServerBaseAddress!)

    @objc public private(set) var analytics: Analytics?

    @objc public weak var delegate: ApplicationDelegate?

    @objc public let notificationCenter: NotificationCenter

    // MARK: - Init

    @objc public init(config: AppConfig) {
        self.config = config
        userDefaults = config.userDefaults
        userDataStore = UserDefaultsStore(userDefaults: userDefaults)
        locationService = config.locationService
        regionsService = config.regionsService
        analytics = config.analytics
        notificationCenter = NotificationCenter.default

        theme = Theme(bundle: config.themeBundle, traitCollection: nil)

        super.init()

        configureAppearanceProxies()

        locationService.addDelegate(self)
        regionsService.addDelegate(self)

        if locationService.isLocationUseAuthorized {
            locationService.startUpdates()
        }

        refreshRESTAPIModelService()
    }

    // MARK: - App State Management

    /// True when the app should show an interstitial location service permission
    /// request user interface. Meant to be called on app launch to determine
    /// which piece of UI should be shown initially.
    @objc public var showPermissionPromptUI: Bool {
        return locationService.canRequestAuthorization
    }

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
        #if targetEnvironment(simulator)
        guard let delegate = delegate as? NSObject & ApplicationDelegate else {
            return false
        }

        return delegate.performTestCrash != nil
        #else
        return false
        #endif
    }

    /// Crashes the app by calling the appropriate delegate method.
    ///
    /// Useful for testing Crashlytics integration, for example.
    func performTestCrash() {
        guard shouldShowCrashButton else { return }
        delegate?.performTestCrash?()
    }

    // MARK: - UIApplication Hooks

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

    // MARK: - Appearance and Themes

    /// Sets default styles for several UIAppearance proxies in order to customize the app's look and feel
    ///
    /// To override the values that are set in here, either customize the theme that this object is
    /// configured with at launch or simply don't call this method and set up your own `UIAppearance`
    /// proxies instead.
    private func configureAppearanceProxies() {
        let tintColor = ThemeColors.shared.primary
        let tintColorTypes = [UIWindow.self, UINavigationBar.self, UISearchBar.self, UISegmentedControl.self, UITabBar.self, UITextField.self, UIButton.self]

        for t in tintColorTypes {
            t.appearance().tintColor = tintColor
        }

        BorderedButton.appearance().setTitleColor(ThemeColors.shared.lightText, for: .normal)
        BorderedButton.appearance().tintColor = ThemeColors.shared.primary

        EmptyDataSetView.appearance().bodyLabelFont = UIFont.preferredFont(forTextStyle: .body)
        EmptyDataSetView.appearance().textColor = ThemeColors.shared.secondaryLabel
        EmptyDataSetView.appearance().titleLabelFont = UIFont.preferredFont(forTextStyle: .title1).bold

        FloatingPanelTitleView.appearance().titleFont = UIFont.preferredFont(forTextStyle: .title2).bold
        FloatingPanelTitleView.appearance().subtitleFont = UIFont.preferredFont(forTextStyle: .body)

        HighlightChangeLabel.appearance().highlightedBackgroundColor = ThemeColors.shared.propertyChanged

        IndeterminateProgressView.appearance().progressColor = ThemeColors.shared.primary

        StackedButton.appearance().font = UIFont.preferredFont(forTextStyle: .footnote)

        StackedTitleView.appearance().subtitleFont = UIFont.preferredFont(forTextStyle: .footnote)
        StackedTitleView.appearance().titleFont = UIFont.preferredFont(forTextStyle: .footnote).bold

        StatusOverlayView.appearance().innerPadding = ThemeMetrics.padding
        StatusOverlayView.appearance().textColor = ThemeColors.shared.lightText

        StopAnnotationView.appearance().annotationSize = ThemeMetrics.defaultMapAnnotationSize
        StopAnnotationView.appearance().bookmarkedStrokeColor = ThemeColors.shared.primary
        StopAnnotationView.appearance().fillColor = UIColor.white
        StopAnnotationView.appearance().mapTextColor = ThemeColors.shared.mapText
        StopAnnotationView.appearance().showsCallout = theme.behaviors.mapShowsCallouts
        StopAnnotationView.appearance().strokeColor = ThemeColors.shared.mapStroke
        StopAnnotationView.appearance().tintColor = ThemeColors.shared.stopAnnotationIcon

        StopArrivalView.appearance().timeExplanationFont = UIFont.preferredFont(forTextStyle: .footnote)

        SubtitleTableCell.appearance().subtitleFont = UIFont.preferredFont(forTextStyle: .footnote)

        TableHeaderView.appearance().font = UIFont.preferredFont(forTextStyle: .footnote)
        TableHeaderView.appearance().textColor = ThemeColors.shared.secondaryLabel

        TableSectionHeaderView.appearance().backgroundColor = ThemeColors.shared.secondaryBackgroundColor

        TripSegmentView.appearance().imageColor = ThemeColors.shared.primary
        TripSegmentView.appearance().lineColor = ThemeColors.shared.gray

        WalkTimeView.appearance().font = UIFont.preferredFont(forTextStyle: .footnote)
        WalkTimeView.appearance().backgroundBarColor = ThemeColors.shared.primary
        WalkTimeView.appearance().textColor = ThemeColors.shared.label

        UIBarButtonItem.appearance().setTitleTextAttributes([.foregroundColor: tintColor], for: .normal)

        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        UISegmentedControl.appearance(whenContainedInInstancesOf: [UINavigationBar.self]).setTitleTextAttributes([.foregroundColor: UIColor.darkText], for: .normal)

        // See: https://github.com/Instagram/IGListKit/blob/master/Guides/Working%20with%20UICollectionView.md
        UICollectionView.appearance().isPrefetchingEnabled = false
    }

    // MARK: - Regions Management

    @objc public func manuallySelectRegion() {
        regionsService.automaticallySelectRegion = false

        let regionPickerController = RegionPickerViewController(application: self, message: .manualSelectionMessage)
        delegate?.application(self, displayRegionPicker: regionPickerController)
    }

    public func regionsServiceUnableToSelectRegion(_ service: RegionsService) {
        manuallySelectRegion()
    }

    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        refreshRESTAPIModelService()
        refreshObacoService()
    }

    /// Recreates the `restAPIModelService` from the current region. This is
    /// called when the app launches and when the current region changes.
    private func refreshRESTAPIModelService() {
        guard let region = regionsService.currentRegion else { return }

        let apiService = RESTAPIService(baseURL: region.OBABaseURL, apiKey: config.apiKey, uuid: config.uuid, appVersion: config.appVersion, networkQueue: config.queue)
        restAPIModelService = RESTAPIModelService(apiService: apiService, dataQueue: config.queue)
    }

    public let obacoServiceUpdatedNotification = NSNotification.Name("ObacoServiceUpdatedNotification")

    /// Reloads the Obaco Service stack, including the network queue, api service manager, and model service manager.
    /// This must be called when the region changes.
    private func refreshObacoService() {
        guard
            let region = regionsService.currentRegion,
            let baseURL = config.obacoBaseURL
        else { return }

        obacoNetworkQueue.cancelAllOperations()

        let apiService = ObacoService(baseURL: baseURL, apiKey: config.apiKey, uuid: config.uuid, appVersion: config.appVersion, regionID: String(region.regionIdentifier), networkQueue: obacoNetworkQueue)
        obacoService = ObacoModelService(apiService: apiService, dataQueue: obacoNetworkQueue)

        notificationCenter.post(name: obacoServiceUpdatedNotification, object: obacoService)
    }

    // MARK: - LocationServiceDelegate

    public func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        reloadRootUserInterface()
    }
}
