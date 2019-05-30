//
//  Application.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/15/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import CoreLocation

@objc(OBAApplicationDelegate)
public protocol ApplicationDelegate {

    /// This method is called when the delegate should reload the `rootViewController`
    /// of the app's window. This is typically done in response to permissions changes.
    @objc func applicationReloadRootInterface(_ app: Application)

    @objc func application(_ app: Application, displayRegionPicker picker: RegionPickerViewController)
}

@objc(OBAApplication)
public class Application: NSObject {

    /// App configuration parameters: API keys, region server, user UUID, and other
    /// configuration values.
    private let config: AppConfig

    @objc public let userDataStore: UserDataStore

    /// Commonly used formatters configured with the user's current, auto-updating locale.
    @objc public let formatters = Formatters(locale: Locale.autoupdatingCurrent)

    /// Provides access to the user's location and heading.
    @objc public let locationService: LocationService

    /// Responsible for figuring out how to navigate between view controllers.
    @objc public lazy var viewRouter = ViewRouter(application: self)

    /// Responsible for managing `Region`s and determining the correct `Region` for the user.
    @objc public let regionsService: RegionsService

    @objc public private(set) var restAPIModelService: RESTAPIModelService?

    @objc public private(set) lazy var mapRegionManager = MapRegionManager(application: self)

    @objc public private(set) lazy var searchManager = SearchManager(application: self)

    @objc public private(set) var theme: Theme

    @objc public weak var delegate: ApplicationDelegate?

    @objc public init(config: AppConfig) {
        self.config = config
        userDataStore = UserDefaultsStore(userDefaults: config.userDefaults)
        locationService = config.locationService
        regionsService = config.regionsService

        theme = Theme(bundle: config.themeBundle, traitCollection: nil)

        super.init()

        locationService.addDelegate(self)
        regionsService.addDelegate(self)

        if locationService.isLocationUseAuthorized {
            locationService.startUpdates()
        }

        refreshRESTAPIModelService()
    }

    private func refreshRESTAPIModelService() {
        guard let region = regionsService.currentRegion else {
            return
        }

        let apiService = RESTAPIService(baseURL: region.OBABaseURL, apiKey: config.apiKey, uuid: config.uuid, appVersion: config.appVersion, networkQueue: config.queue)
        restAPIModelService = RESTAPIModelService(apiService: apiService, dataQueue: config.queue)
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

    // MARK: - Appearance and Themes

    /// Sets default styles for several UIAppearance proxies in order to customize the app's look and feel
    ///
    /// To override the values that are set in here, either customize the theme that this object is
    /// configured with at launch or simply don't call this method and set up your own `UIAppearance`
    /// proxies instead.
    @objc public func configureAppearanceProxies() {
        let tintColor = theme.colors.primary
        let tintColorTypes = [UIWindow.self, UINavigationBar.self, UISearchBar.self, UISegmentedControl.self, UITabBar.self, UITextField.self, UIButton.self]

        for t in tintColorTypes {
            t.appearance().tintColor = tintColor
        }

        BorderedButton.appearance().setTitleColor(theme.colors.lightText, for: .normal)
        BorderedButton.appearance().tintColor = theme.colors.dark

        FloatingPanelTitleView.appearance().subtitleFont = theme.fonts.footnote
        FloatingPanelTitleView.appearance().titleFont = theme.fonts.title

        IndeterminateProgressView.appearance().progressColor = theme.colors.primary

        StackedButton.appearance().font = theme.fonts.footnote

        StatusOverlayView.appearance().innerPadding = theme.metrics.padding
        StatusOverlayView.appearance().textColor = theme.colors.lightText

        StopAnnotationView.appearance().theme = theme
        StopArrivalView.appearance().formatters = formatters

        SubtitleTableCell.appearance().subtitleFont = theme.fonts.footnote
        SubtitleTableCell.appearance().subtitleTextColor = theme.colors.subduedText

        UIBarButtonItem.appearance().setTitleTextAttributes([.foregroundColor: tintColor], for: .normal)

        UIButton.appearance().setTitleColor(theme.colors.dark, for: .normal)

        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        UISegmentedControl.appearance(whenContainedInInstancesOf: [UINavigationBar.self]).setTitleTextAttributes([.foregroundColor: UIColor.darkText], for: .normal)

        // See: https://github.com/Instagram/IGListKit/blob/master/Guides/Working%20with%20UICollectionView.md
        UICollectionView.appearance().isPrefetchingEnabled = false

//
//        [[UITableViewCell appearance] setPreservesSuperviewLayoutMargins:YES];
//        [[[UITableViewCell appearance] contentView] setPreservesSuperviewLayoutMargins:YES];
//
    }
}

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
}

extension Application: LocationServiceDelegate {
    public func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        reloadRootUserInterface()
    }
}
