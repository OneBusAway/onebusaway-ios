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

    /// This proxies the `isIdleTimerDisabled` property on UIApplication, which prevents
    /// the screen from turning off when it is set to `true`.
    @objc(idleTimerDisabled) var isIdleTimerDisabled: Bool { get set }

    /// Proxies `UIApplication.canOpenURL()`
    /// - Parameter url: The URL that we are checking can be opened.
    @objc func canOpenURL(_ url: URL) -> Bool

    /// Proxies the equivalent method on `UIApplication`
    @objc func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any], completionHandler completion: ((Bool) -> Void)?)
}

@objc(OBAApplication)
public class Application: NSObject {

    // MARK: - Private Properties

    /// App configuration parameters: API keys, region server, user UUID, and other
    /// configuration values.
    private let config: AppConfig

    // MARK: - Public Properties

    @objc public let userDataStore: UserDataStore

    /// Commonly used formatters configured with the user's current, auto-updating locale and the app's theme colors.
    @objc public lazy var formatters = Formatters(locale: Locale.autoupdatingCurrent, themeColors: theme.colors)

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

    /// Provides access to the OneBusAway REST API
    ///
    /// - Note: See [develop.onebusaway.org](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/index.html)
    ///         for more information on the REST API.
    @objc public private(set) var restAPIModelService: RESTAPIModelService?

    @objc public private(set) lazy var mapRegionManager = MapRegionManager(application: self)

    @objc public private(set) lazy var searchManager = SearchManager(application: self)

    @objc public private(set) var theme: Theme

    @objc public private(set) lazy var userActivityBuilder = UserActivityBuilder(application: self)

    @objc public private(set) lazy var deepLinkRouter = DeepLinkRouter(baseURL: applicationBundle.deepLinkServerBaseAddress!)

    @objc public weak var delegate: ApplicationDelegate?

    // MARK: - Init

    @objc public init(config: AppConfig) {
        self.config = config
        userDataStore = UserDefaultsStore(userDefaults: config.userDefaults)
        locationService = config.locationService
        regionsService = config.regionsService

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

    // MARK: - UIApplication Hooks

    public var isIdleTimerDisabled: Bool {
        get {
            return (delegate?.isIdleTimerDisabled ?? false)
        }
        set {
            delegate?.isIdleTimerDisabled = newValue
        }
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

    // MARK: - Appearance and Themes

    /// Sets default styles for several UIAppearance proxies in order to customize the app's look and feel
    ///
    /// To override the values that are set in here, either customize the theme that this object is
    /// configured with at launch or simply don't call this method and set up your own `UIAppearance`
    /// proxies instead.
    private func configureAppearanceProxies() {
        let tintColor = theme.colors.primary
        let tintColorTypes = [UIWindow.self, UINavigationBar.self, UISearchBar.self, UISegmentedControl.self, UITabBar.self, UITextField.self, UIButton.self]

        for t in tintColorTypes {
            t.appearance().tintColor = tintColor
        }

        BorderedButton.appearance().setTitleColor(theme.colors.lightText, for: .normal)
        BorderedButton.appearance().tintColor = theme.colors.dark

        EmptyDataSetView.appearance().bodyLabelFont = theme.fonts.body
        EmptyDataSetView.appearance().textColor = theme.colors.subduedText
        EmptyDataSetView.appearance().titleLabelFont = theme.fonts.largeTitle

        FloatingPanelTitleView.appearance().subtitleFont = theme.fonts.footnote
        FloatingPanelTitleView.appearance().titleFont = theme.fonts.title

        HighlightChangeLabel.appearance().highlightedBackgroundColor = theme.colors.propertyChanged

        IndeterminateProgressView.appearance().progressColor = theme.colors.primary

        StackedButton.appearance().font = theme.fonts.footnote

        StatusOverlayView.appearance().innerPadding = ThemeMetrics.padding
        StatusOverlayView.appearance().textColor = theme.colors.lightText

        StopAnnotationView.appearance().annotationSize = ThemeMetrics.defaultMapAnnotationSize
        StopAnnotationView.appearance().fillColor = theme.colors.primary
        StopAnnotationView.appearance().mapTextColor = theme.colors.mapText
        StopAnnotationView.appearance().mapTextFont = theme.fonts.mapAnnotation
        StopAnnotationView.appearance().showsCallout = theme.behaviors.mapShowsCallouts
        StopAnnotationView.appearance().tintColor = theme.colors.stopAnnotationIcon

        SubtitleTableCell.appearance().subtitleFont = theme.fonts.footnote
        SubtitleTableCell.appearance().subtitleTextColor = theme.colors.subduedText

        TableHeaderView.appearance().font = theme.fonts.boldFootnote
        TableHeaderView.appearance().textColor = theme.colors.subduedText

        WalkTimeView.appearance().font = theme.fonts.footnote
        WalkTimeView.appearance().backgroundBarColor = theme.colors.primary
        WalkTimeView.appearance().textColor = theme.colors.lightText

        UIBarButtonItem.appearance().setTitleTextAttributes([.foregroundColor: tintColor], for: .normal)

        UIButton.appearance().setTitleColor(theme.colors.dark, for: .normal)

        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        UISegmentedControl.appearance(whenContainedInInstancesOf: [UINavigationBar.self]).setTitleTextAttributes([.foregroundColor: UIColor.darkText], for: .normal)

        // See: https://github.com/Instagram/IGListKit/blob/master/Guides/Working%20with%20UICollectionView.md
        UICollectionView.appearance().isPrefetchingEnabled = false
    }
}

// MARK: - Regions Management

extension Application: RegionsServiceDelegate {
    @objc public func manuallySelectRegion() {
        let regionPickerController = RegionPickerViewController(application: self)
        delegate?.application(self, displayRegionPicker: regionPickerController)
    }

    public func regionsServiceUnableToSelectRegion(_ service: RegionsService) {
        manuallySelectRegion()
    }

    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        refreshRESTAPIModelService()
    }

    /// Recreates the `restAPIModelService` from the current region. This is
    /// called when the app launches and when the current region changes.
    private func refreshRESTAPIModelService() {
        guard let region = regionsService.currentRegion else { return }

        let apiService = RESTAPIService(baseURL: region.OBABaseURL, apiKey: config.apiKey, uuid: config.uuid, appVersion: config.appVersion, networkQueue: config.queue)
        restAPIModelService = RESTAPIModelService(apiService: apiService, dataQueue: config.queue)
    }
}

// MARK: - LocationServiceDelegate

extension Application: LocationServiceDelegate {
    public func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        reloadRootUserInterface()
    }
}
