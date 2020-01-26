//
//  CoreApplication.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 1/26/20.
//

import Foundation
import CoreLocation

@objc(OBACoreApplication)
open class CoreApplication: NSObject,
    AgencyAlertsDelegate,
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
    @objc public lazy var regionsService = RegionsService(modelService: regionsModelService, locationService: locationService, userDefaults: userDefaults, bundledRegionsFilePath: self.config.bundledRegionsFilePath, apiPath: self.config.regionsAPIPath)

    /// Helper property that returns `regionsService.currentRegion`.
    @objc public var currentRegion: Region? {
        return regionsService.currentRegion
    }

    /// Provides access to the OneBusAway REST API
    ///
    /// - Note: See [develop.onebusaway.org](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/index.html)
    ///         for more information on the REST API.
    @objc public private(set) var restAPIModelService: RESTAPIModelService? {
        didSet {
            alertsStore.restModelService = restAPIModelService
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

        refreshRESTAPIModelService()
        refreshObacoService()
    }

    // MARK: - Agency Alerts

    public var shouldDisplayRegionalTestAlerts: Bool {
        return userDefaults.bool(forKey: AgencyAlertsStore.UserDefaultKeys.displayRegionalTestAlerts)
    }

    public lazy var alertsStore = AgencyAlertsStore(userDefaults: userDefaults)

    // MARK: - LocationServiceDelegate

    public func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        // nop?
    }

    // MARK: - REST API

    /// Recreates the `restAPIModelService` from the current region. This is
    /// called when the app launches and when the current region changes.
    private func refreshRESTAPIModelService() {
        guard let region = regionsService.currentRegion else { return }

        let apiService = RESTAPIService(baseURL: region.OBABaseURL, apiKey: config.apiKey, uuid: userUUID, appVersion: config.appVersion, networkQueue: config.queue)
        restAPIModelService = RESTAPIModelService(apiService: apiService, dataQueue: config.queue)
    }

    // MARK: - Obaco

    @objc public private(set) var obacoService: ObacoModelService? {
        didSet {
            notificationCenter.post(name: obacoServiceUpdatedNotification, object: obacoService)
            alertsStore.obacoModelService = obacoService
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

        obacoNetworkQueue.cancelAllOperations()

        let apiService = ObacoService(baseURL: baseURL, apiKey: config.apiKey, uuid: userUUID, appVersion: config.appVersion, regionID: String(region.regionIdentifier), networkQueue: obacoNetworkQueue, delegate: self)
        obacoService = ObacoModelService(apiService: apiService, dataQueue: obacoNetworkQueue)
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

    private lazy var regionsAPIService = RegionsAPIService(baseURL: config.regionsBaseURL, apiKey: config.apiKey, uuid: userUUID, appVersion: config.appVersion, networkQueue: config.queue)

    private lazy var regionsModelService = RegionsModelService(apiService: regionsAPIService, dataQueue: config.queue)

    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        refreshRESTAPIModelService()
        refreshObacoService()
    }
}
