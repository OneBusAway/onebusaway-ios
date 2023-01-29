//
//  RegionsService.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

@objc(OBARegionsServiceDelegate)
public protocol RegionsServiceDelegate: NSObjectProtocol {
    @objc optional func regionsServiceUnableToSelectRegion(_ service: RegionsService)
    @objc optional func regionsService(_ service: RegionsService, updatedRegionsList regions: [Region])
    @objc optional func regionsService(_ service: RegionsService, willUpdateToRegion region: Region)
    @objc optional func regionsService(_ service: RegionsService, updatedRegion region: Region)
    @objc optional func regionsService(_ service: RegionsService, changedAutomaticRegionSelection value: Bool)

    /// This delegate method is called when the region list update is cancelled before retrieving data.
    ///
    /// The update will be cancelled when the regions list has been updated within the past week, and an update is not forced.
    /// - parameter service: The `RegionsService` object.
    @objc optional func regionsServiceListUpdateCancelled(_ service: RegionsService)

    @objc optional func regionsService(_ service: RegionsService, displayError error: Error)
}

/// Manages the app's list of `Region`s, including list updates, and which `Region` the user is currently located in.
public class RegionsService: NSObject, LocationServiceDelegate {
    private let apiService: RegionsAPIService?
    private let locationService: LocationService
    private let userDefaults: UserDefaults
    private let bundledRegionsFilePath: String
    private let apiPath: String?

    /// Initializes a `RegionsService` object, which coordinates the current region, downloading new data, and storage.
    /// - Parameters:
    ///   - apiService: Retrieves new data from the region server and turns it into models.
    ///   - locationService: A location service object.
    ///   - userDefaults: The user defaults object.
    ///   - bundledRegionsFilePath: The path to the bundled regions file. It is probably named "regions.json" or something similar.
    ///   - apiPath: The path to the remote regions.json file on the server. e.g. /path/to/regions.json
    ///   - delegate: A delegate object for callbacks.
    public init(apiService: RegionsAPIService?, locationService: LocationService, userDefaults: UserDefaults, bundledRegionsFilePath: String, apiPath: String?, delegate: RegionsServiceDelegate? = nil) {
        self.apiService = apiService
        self.locationService = locationService
        self.userDefaults = userDefaults
        self.bundledRegionsFilePath = bundledRegionsFilePath
        self.apiPath = apiPath

        self.userDefaults.register(defaults: [
            RegionsService.automaticallySelectRegionUserDefaultsKey: true,
            RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey: false
        ])

        if let regions = RegionsService.loadStoredRegions(from: userDefaults), regions.count > 0 {
            self.regions = regions
        }
        else {
            self.regions = RegionsService.bundledRegions(path: bundledRegionsFilePath)
        }

        super.init()

        if let delegate = delegate {
            addDelegate(delegate)
        }

        let autoSelectRegion = userDefaults.bool(forKey: RegionsService.automaticallySelectRegionUserDefaultsKey) || currentRegion == nil

        if autoSelectRegion, let location = locationService.currentLocation {
            currentRegion = RegionsService.firstRegion(in: self.regions, containing: location)
        }

        self.locationService.addDelegate(self)
    }

    // MARK: - Delegates

    private let delegates = NSHashTable<RegionsServiceDelegate>.weakObjects()

    public func addDelegate(_ delegate: RegionsServiceDelegate) {
        delegates.add(delegate)
    }

    public func removeDelegate(_ delegate: RegionsServiceDelegate) {
        delegates.remove(delegate)
    }

    private func notifyDelegatesRegionChanged(_ region: Region) {
        for delegate in delegates.allObjects {
            delegate.regionsService?(self, willUpdateToRegion: region)
        }

        for delegate in delegates.allObjects {
            delegate.regionsService?(self, updatedRegion: region)
        }
    }

    private func notifyDelegatesRegionsListUpdated() {
        for delegate in delegates.allObjects {
            delegate.regionsService?(self, updatedRegionsList: regions)
        }
    }

    private func notifyDelegatesUnableToSelectRegion() {
        for delegate in delegates.allObjects {
            delegate.regionsServiceUnableToSelectRegion?(self)
        }
    }

    private func notifyDelegatesRegionListUpdateCancelled() {
        for delegate in delegates.allObjects {
            delegate.regionsServiceListUpdateCancelled?(self)
        }
    }

    private func notifyDelegatesAutomaticallySelectRegionChanged(value: Bool) {
        for delegate in delegates.allObjects {
            delegate.regionsService?(self, changedAutomaticRegionSelection: value)
        }
    }

    private func notifyDelegatesDisplayError(_ error: Error) {
        for delegate in delegates.allObjects {
            delegate.regionsService?(self, displayError: error)
        }
    }

    // MARK: - Regions Data

    public private(set) var regions: [Region] {
        didSet {
            if regions.count > 0 {
                storeRegions()
                notifyDelegatesRegionsListUpdated()
                updateCurrentRegionFromLocation()
            }
        }
    }

    /// The app's currently-selected `Region`. Note that this may be different from `physicallyLocatedRegion`.
    public var currentRegion: Region? {
        get {
            do {
                return try userDefaults.decodeUserDefaultsObjects(type: Region.self, key: RegionsService.currentRegionUserDefaultsKey)
            }
            catch let error {
                Logger.error("Unable to read region from user defaults: \(error)")
                return nil
            }
        }
        set {
            guard
                let newValue = newValue,
                newValue != currentRegion
            else {
                return
            }

            do {
                try userDefaults.encodeUserDefaultsObjects(newValue, key: RegionsService.currentRegionUserDefaultsKey)
                notifyDelegatesRegionChanged(newValue)
            }
            catch {
                Logger.error("Unable to write currentRegion to user defaults: \(error)")
            }
        }
    }

    /// The `Region`, if one exists, that the user is physically located in. Note that this may be different from `currentRegion`.
    public var physicallyLocatedRegion: Region? {
        guard let location = locationService.currentLocation else {
            return nil
        }

        return RegionsService.firstRegion(in: regions, containing: location)
    }

    public var automaticallySelectRegion: Bool {
        get {
            userDefaults.bool(forKey: RegionsService.automaticallySelectRegionUserDefaultsKey)
        }
        set {
            userDefaults.set(newValue, forKey: RegionsService.automaticallySelectRegionUserDefaultsKey)
            if newValue {
                // When this value toggles to true, we should refresh the current region.
                updateCurrentRegionFromLocation()
            }
            notifyDelegatesAutomaticallySelectRegionChanged(value: newValue)
        }
    }

    public func find(id: Int) -> Region? {
        if let region = regions.first(where: { $0.regionIdentifier == id }) {
            return region
        }
        else {
            return customRegions.first { $0.regionIdentifier == id }
        }
    }

    // MARK: - Custom Regions

    @available(*, deprecated, renamed: "add(customRegion:)")
    public func addCustomRegion(_ region: Region) {
        Task {
            do {
                try await add(customRegion: region)
            }
            catch {
                Logger.error("Unable to write custom regions to user defaults: \(error)")
            }
        }
    }

    /// Adds the provided custom region to the RegionsService.
    /// If an existing custom region with the same `regionIdentifier` exists, the new region replaces the existing region.
    /// - throws: Persistence storage errors.
    public func add(customRegion newRegion: Region) async throws {
        var regions = customRegions
        if let index = regions.firstIndex(where: { $0.regionIdentifier == newRegion.regionIdentifier }) {
            regions.remove(at: index)
        }

        regions.append(newRegion)

        try userDefaults.encodeUserDefaultsObjects(regions, key: RegionsService.storedCustomRegionsUserDefaultsKey)
    }

    /// Deletes the custom region. If the region could not be found, this method exits normally.
    /// - parameter customRegion: The custom region to delete.
    /// - throws: If `customRegion` is not a custom region, this method will throw.
    public func delete(customRegion: Region) async throws {
        try await delete(customRegionIdentifier: customRegion.regionIdentifier)
    }

    /// Deletes the custom region with the matching identifier. If a region with the given identifier could not be found, this method exits normally.
    /// - parameter identifier: The region identifier used to find the custom region to delete.
    /// - throws: If a custom region with the provided `identifier` could not be found, or is not a custom region, this method will throw.
    public func delete(customRegionIdentifier identifier: RegionIdentifier) async throws {
        var regions = customRegions

        guard let index = regions.firstIndex(where: { $0.regionIdentifier == identifier }) else {
            return
        }

        regions.remove(at: index)
        try userDefaults.encodeUserDefaultsObjects(regions, key: RegionsService.storedCustomRegionsUserDefaultsKey)
    }

    /// Deletes the custom region with the matching identifier.
    /// - Parameter identifier: The region identifier used to find the custom region to delete.
    /// - Returns: True if the custom region was found and deleted, and false if it could not be found.
    @available(*, deprecated, renamed: "delete(customRegionIdentifier:)")
    @discardableResult public func deleteCustomRegion(identifier: RegionIdentifier) -> Bool {
        var success = false
        var regions = customRegions

        if let idx = regions.firstIndex(where: { $0.regionIdentifier == identifier }) {
            regions.remove(at: idx)

            do {
                try userDefaults.encodeUserDefaultsObjects(regions, key: RegionsService.storedCustomRegionsUserDefaultsKey)
                success = true
            }
            catch {
                Logger.error("Unable to write custom regions to user defaults: \(error)")
            }
        }

        return success
    }

    public var customRegions: [Region] {
        let regions: [Region]
        do {
            regions = try userDefaults.decodeUserDefaultsObjects(type: [Region].self, key: RegionsService.storedCustomRegionsUserDefaultsKey) ?? []
        } catch {
            regions = []
        }
        return regions
    }

    public var allRegions: [Region] {
        return regions + customRegions
    }

    // MARK: - Region Data Storage

    public static let alwaysRefreshRegionsOnLaunchUserDefaultsKey = "OBAAlwaysRefreshRegionsOnLaunchUserDefaultsKey"
    static let automaticallySelectRegionUserDefaultsKey = "OBAAutomaticallySelectRegionUserDefaultsKey"
    static let storedRegionsUserDefaultsKey = "OBAStoredRegionsUserDefaultsKey"
    static let storedCustomRegionsUserDefaultsKey = "OBAStoredCustomRegionsUserDefaultsKey"
    static let currentRegionUserDefaultsKey = "OBACurrentRegionUserDefaultsKey"
    static let regionsUpdatedAtUserDefaultsKey = "OBARegionsUpdatedAtUserDefaultsKey"

    // MARK: - Save Regions

    private func storeRegions() {
        do {
            try userDefaults.encodeUserDefaultsObjects(regions, key: RegionsService.storedRegionsUserDefaultsKey)
            userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)
        }
        catch {
            Logger.error("Unable to write regions to user defaults: \(error)")
        }
    }

    // MARK: - Load Stored Regions

    private class func loadStoredRegions(from userDefaults: UserDefaults) -> [Region]? {
        let regions: [Region]

        do {
            regions = try userDefaults.decodeUserDefaultsObjects(type: [Region].self, key: RegionsService.storedRegionsUserDefaultsKey) ?? []
        } catch {
            return nil
        }

        if regions.count == 0 {
            return nil
        }
        else {
            return regions
        }
    }

    // MARK: - Bundled Regions

    // swiftlint:disable force_try

    private static func bundledRegions(path: String) -> [Region] {
        let data = try! NSData(contentsOfFile: path) as Data
        let response = try! JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[Region]>.self, from: data)
        return response.list
    }

    // swiftlint:enable force_try

    // MARK: - Update Helpers

    /// Returns `true` if the list of `Region`s should be updated from the server.
    ///
    /// By default, this method only returns `true` if it has been at least a week since the last successful refresh,
    /// however you can override this to force it to update the list of `Region`s on every launch if you set the
    /// `UserDefaults` key `RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey` to `true`.
    /// You can set this value to `true` either through some console trickery, or by toggling the setting in the Settings controller
    /// when Debug Mode is enabled in the `MoreViewController`.
    var shouldUpdateRegionList: Bool {
        if userDefaults.bool(forKey: RegionsService.alwaysRefreshRegionsOnLaunchUserDefaultsKey) {
            return true
        }

        guard let lastUpdatedAt = userDefaults.object(forKey: RegionsService.regionsUpdatedAtUserDefaultsKey) as? Date else {
            return true
        }

        // True if it has been at least the number of seconds in a week since the last update.
        return abs(lastUpdatedAt.timeIntervalSinceNow) >= 604800
    }

    // MARK: - Public Methods

    /// Fetches the current list of `Region`s from the network.
    public func refreshRegions() async throws {
        guard let apiService, let apiPath else {
            return
        }

        let regions = try await apiService.getRegions(apiPath: apiPath).list
        guard !regions.isEmpty else {
            return
        }

        self.regions = regions
    }

    /// Fetches the current list of `Region`s from the network.
    /// - Parameter forceUpdate: Forces an update of the regions list, even if the last update happened less than one week ago.
    public func updateRegionsList(forceUpdate: Bool = false) async {
        // only update once per week, unless forceUpdate is true.
        if !shouldUpdateRegionList && !forceUpdate {
            notifyDelegatesRegionListUpdateCancelled()
            return
        }

        do {
            try await refreshRegions()
            updateCurrentRegionFromLocation()
        } catch {
            notifyDelegatesDisplayError(error)
        }
    }

    // MARK: - LocationServiceDelegate

    public func locationService(_ service: LocationService, locationChanged location: CLLocation) {
        updateCurrentRegionFromLocation()
    }

    private class func firstRegion(in regions: [Region], containing location: CLLocation) -> Region? {
        return (regions.filter { $0.contains(location: location) }).first
    }

    /// Refreshes the `currentRegion` based upon the user's current location.
    /// - Note: If `locationService.currentLocation` returns `nil`, then this method will do nothing.
    public func updateCurrentRegionFromLocation() {
        // We can't do anything here if we can't get the user's current location.
        // Also, don't set the user's region if they've specifically told us not to.
        guard
            locationService.currentLocation != nil,
            automaticallySelectRegion
        else {
            return
        }

        // Prompt the user if their current location doesn't match a region.
        guard let newRegion = physicallyLocatedRegion else {
            notifyDelegatesUnableToSelectRegion()
            return
        }

        currentRegion = newRegion
    }
}
