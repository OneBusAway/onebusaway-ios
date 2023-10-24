//
//  CoreApplication.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

/// Responsible for creating the base application 'stack': API service, regions, and everything else that makes the app run.
///
/// - Note: See `OBAKit.Application` for a richer version of this class suitable for use in an iOS app.
@objc(OBACoreApplication)
open class CoreApplication: NSObject,
    AgencyAlertsDelegate,
    DataMigrationDelegate,
    LocationServiceDelegate,
    ObacoServiceDelegate,
    RegionsServiceDelegate {

    /// App configuration parameters: API keys, region server, user UUID, and other
    /// configuration values.
    private let config: CoreAppConfig

    /// Shared user defaults
    @objc public let userDefaults: UserDefaults

    /// The underlying implementation of our data stores.
    private let userDefaultsStore: UserDefaultsStore

    /// The data store for information like bookmarks, groups, and recent stops.
    @objc public var userDataStore: UserDataStore {
        return userDefaultsStore
    }

    /// The data store for `StopPreference` data.
    public var stopPreferencesDataStore: StopPreferencesStore {
        return userDefaultsStore
    }

    @objc public let notificationCenter: NotificationCenter

    /// Provides access to the user's location and heading.
    @objc public let locationService: LocationService

    /// Responsible for managing `Region`s and determining the correct `Region` for the user.
    @objc public lazy var regionsService = RegionsService(apiService: regionsAPIService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: self.config.bundledRegionsFilePath, apiPath: self.config.regionsAPIPath)

    /// Helper property that returns `regionsService.currentRegion`.
    @objc public var currentRegion: Region? {
        return regionsService.currentRegion
    }

    /// Provides access to the OneBusAway REST API
    ///
    /// - Note: See [develop.onebusaway.org](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/index.html)
    ///         for more information on the REST API.
    public private(set) var apiService: RESTAPIService? {
        didSet {
            alertsStore.apiService = apiService
        }
    }

    /// Commonly used formatters configured with the user's current, auto-updating locale and calendar, and the app's theme colors.
    @objc public lazy var formatters = Formatters(locale: Locale.autoupdatingCurrent, calendar: Calendar.autoupdatingCurrent, themeColors: ThemeColors.shared)

    @objc public let locale = Locale.autoupdatingCurrent

    public init(config: CoreAppConfig) {
        self.config = config

        userDefaults = config.userDefaults
        userDefaultsStore = UserDefaultsStore(userDefaults: userDefaults)

        locationService = config.locationService
        notificationCenter = NotificationCenter.default

        super.init()

        locationService.addDelegate(self)
        regionsService.addDelegate(self)
        alertsStore.addDelegate(self)

        Task {
            await regionsService.updateRegionsList()
        }
        refreshRESTAPIService()
        refreshObacoService()
    }

    // MARK: - Agency Alerts

    public var shouldDisplayRegionalTestAlerts: Bool {
        return userDefaults.bool(forKey: AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts)
    }

    public lazy var alertsStore = AgencyAlertsStore(userDefaults: userDefaults, regionsService: regionsService)

    // MARK: - LocationServiceDelegate

    public func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        // nop?
    }

    // MARK: - REST API

    /// Recreates the `restAPIService` from the current region. This is
    /// called when the app launches and when the current region changes.
    private func refreshRESTAPIService() {
        guard let region = regionsService.currentRegion else {
            return
        }

        self.apiService = RESTAPIService(APIServiceConfiguration(baseURL: region.OBABaseURL, apiKey: config.apiKey, uuid: userUUID, appVersion: config.appVersion, regionIdentifier: region.regionIdentifier))
    }

    // MARK: - Obaco

    public private(set) var obacoService: ObacoAPIService? {
        didSet {
            notificationCenter.post(name: obacoServiceUpdatedNotification, object: obacoService)
            alertsStore.obacoService = obacoService
        }
    }

    private var obacoNetworkQueue = OperationQueue()

    public let obacoServiceUpdatedNotification = NSNotification.Name("ObacoServiceUpdatedNotification")

    /// Reloads the Obaco Service stack, including the network queue, api service manager, and model service manager.
    /// This must be called when the region changes.
    private func refreshObacoService() {
        guard
            let region = regionsService.currentRegion,
            let baseURL = config.obacoBaseURL
        else { return }

        let configuration = APIServiceConfiguration(baseURL: baseURL, apiKey: config.apiKey, uuid: userUUID, appVersion: config.appVersion, regionIdentifier: region.regionIdentifier)
        obacoService = ObacoAPIService(regionID: region.regionIdentifier, delegate: self, configuration: configuration, dataLoader: config.dataLoader)
    }

    // MARK: - UUID

    private let userUUIDDefaultsKey = "userUUIDDefaultsKey"

    /// A unique (but not personally-identifying) identifier for the current user that is used
    /// to correlate crash logs and other events to a single person.
    @objc public var userUUID: String {
        if let uuid = userDefaults.object(forKey: userUUIDDefaultsKey) as? String {
            return uuid
        }
        else {
            let uuid = UUID().uuidString
            userDefaults.set(uuid, forKey: userUUIDDefaultsKey)
            return uuid
        }
    }

    // MARK: - Regions Service

    private lazy var regionsAPIService: RegionsAPIService? = {
        guard let regionsBaseURL = config.regionsBaseURL else {
            return nil
        }

        let configuration = APIServiceConfiguration(
            baseURL: regionsBaseURL,
            apiKey: config.apiKey,
            uuid: userUUID,
            appVersion: config.appVersion,
            regionIdentifier: nil
        )

        return RegionsAPIService(configuration, dataLoader: config.dataLoader)
    }()

    open func regionsService(_ service: RegionsService, willUpdateToRegion region: Region) {
        refreshRESTAPIService()
        refreshObacoService()
    }

    open func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        // nop
    }

    // MARK: - Migration

    public func migrate(userID: String) {
        userDefaults.set(userID, forKey: userUUIDDefaultsKey)
    }

    public func migrate(region: MigrationRegion) {
        if let newRegion = regionsService.find(id: region.identifier) {
            regionsService.currentRegion = newRegion
        }
    }

    public func migrate(recentStop: Stop) {
        guard let currentRegion = currentRegion else { return }
        fatalError("\(#function) unimplemented.")
//        userDataStore.addRecentStop(recentStop, region: currentRegion)
    }

    public func migrate(bookmark: Bookmark, group: BookmarkGroup?) {
        userDataStore.add(bookmark, to: group)
    }

    // MARK: - Error Handling

    @MainActor
    open func displayError(_ error: Error) async {
        Logger.error("Error: \(error.localizedDescription)")
    }
}
