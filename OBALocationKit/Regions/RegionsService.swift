//
//  RegionsService.swift
//  OBALocationKit
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import OBANetworkingKit
import CoreLocation

@objc(OBARegionsServiceDelegate)
public protocol RegionsServiceDelegate {
    func regionsServiceUnableToSelectRegion(_ service: RegionsService)
    func regionsService(_ service: RegionsService, updatedRegion region: Region)
}

@objc(OBARegionsService)
public class RegionsService: NSObject {
    private let modelService: RegionsModelService
    private let locationService: LocationService
    private let userDefaults: UserDefaults

    public init(modelService: RegionsModelService, locationService: LocationService, userDefaults: UserDefaults) {
        self.modelService = modelService
        self.locationService = locationService
        self.userDefaults = userDefaults

        let regions = RegionsService.loadStoredRegions(from: userDefaults)
        self.regions = regions

        if let currentRegion = RegionsService.loadCurrentRegion(from: userDefaults) {
            self.currentRegion = currentRegion
        }
        else if let location = locationService.currentLocation {
            self.currentRegion = RegionsService.firstRegion(in: regions, containing: location)
        }

        super.init()

        updateRegionsList()

        self.locationService.addDelegate(self)
    }

    // MARK: - Delegates

    private let delegates = NSHashTable<RegionsServiceDelegate>.weakObjects()

    @objc
    public func addDelegate(_ delegate: RegionsServiceDelegate) {
        delegates.add(delegate)
    }

    @objc
    public func removeDelegate(_ delegate: RegionsServiceDelegate) {
        delegates.remove(delegate)
    }

    private func notifyDelegatesRegionChanged(_ region: Region) {
        for delegate in delegates.allObjects {
            delegate.regionsService(self, updatedRegion: region)
        }
    }

    private func notifyDelegatesUnableToSelectRegion() {
        for delegate in delegates.allObjects {
            delegate.regionsServiceUnableToSelectRegion(self)
        }
    }

    // MARK: - Regions Data

    @objc
    public private(set) var regions: [Region] {
        didSet {
            storeRegions()
            updateCurrentRegion()
        }
    }

    @objc
    public private(set) var currentRegion: Region? {
        didSet {
            if let currentRegion = currentRegion {
                notifyDelegatesRegionChanged(currentRegion)
            }

            storeCurrentRegion()
        }
    }
}

// MARK: - Region Data Storage
extension RegionsService {
    private static let storedRegionsUserDefaultsKey = "OBAStoredRegionsUserDefaultsKey"
    private static let currentRegionUserDefaultsKey = "OBACurrentRegionUserDefaultsKey"
    private static let regionsUpdatedAtUserDefaultsKey = "OBARegionsUpdatedAtUserDefaultsKey"

    // MARK: - Save Regions

    private func storeRegions() {
        do {
            let regionsData = try PropertyListEncoder().encode(regions)
            userDefaults.set(regionsData, forKey: RegionsService.storedRegionsUserDefaultsKey)
            userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)
        }
        catch {
            print("Unable to write regions to user defaults: \(error)")
        }
    }

    private func storeCurrentRegion() {
        guard let currentRegion = currentRegion else {
            return
        }

        do {
            let encoded = try PropertyListEncoder().encode(currentRegion)
            userDefaults.set(encoded, forKey: RegionsService.currentRegionUserDefaultsKey)
        }
        catch {
            print("Unable to write currentRegion to user defaults: \(error)")
        }
    }

    // MARK: - Load Stored Regions

    private class func loadStoredRegions(from userDefaults: UserDefaults) -> [Region] {
        guard
            let regionsData = userDefaults.object(forKey: storedRegionsUserDefaultsKey) as? Data,
            let regions = try? PropertyListDecoder().decode([Region].self, from: regionsData),
            regions.count > 0
        else {
            return bundledRegions
        }

        return regions
    }

    private class func loadCurrentRegion(from userDefaults: UserDefaults) -> Region? {
        guard let encodedData = userDefaults.object(forKey: currentRegionUserDefaultsKey) as? Data else {
            return nil
        }

        return try? PropertyListDecoder().decode(Region.self, from: encodedData)
    }

    // MARK: - Bundled Regions

    private class var bundledRegions: [Region] {
        let bundle = Bundle(for: self)
        let bundledRegionsFilePath = bundle.path(forResource: "regions-v3", ofType: "json")!
        let data = try! NSData(contentsOfFile: bundledRegionsFilePath) as Data
        return DictionaryDecoder.decodeRegionsFileData(data)
    }
}

extension RegionsService {
    public func updateRegionsList(forceUpdate: Bool = false) {
        // only update once per week, unless forceUpdate is true.
        if let lastUpdatedAt = userDefaults.object(forKey: RegionsService.regionsUpdatedAtUserDefaultsKey) as? Date,
           abs(lastUpdatedAt.timeIntervalSinceNow) < 604800,
           !forceUpdate {
            return
        }

        let op = modelService.getRegions()
        op.completionBlock = { [weak self] in
            guard let self = self else {
                return
            }

            self.regions = op.regions
            self.updateCurrentRegion()
        }
    }
}

// MARK: - Region Updates
extension RegionsService: LocationServiceDelegate {
    public func locationService(_ service: LocationService, locationChanged location: CLLocation) {
        updateCurrentRegion()
    }

    private class func firstRegion(in regions: [Region], containing location: CLLocation) -> Region? {
        return (regions.filter { $0.contains(location: location) }).first
    }

    private func updateCurrentRegion() {
        guard let location = locationService.currentLocation else {
            return
        }

        guard let newRegion = RegionsService.firstRegion(in: regions, containing: location) else {
            notifyDelegatesUnableToSelectRegion()
            return
        }

        currentRegion = newRegion
    }
}
