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

    public weak var delegate: RegionsServiceDelegate?

    public init(modelService: RegionsModelService, locationService: LocationService, userDefaults: UserDefaults) {
        self.modelService = modelService
        self.locationService = locationService
        self.userDefaults = userDefaults
        self.regions = RegionsService.loadStoredRegions(from: userDefaults)
        self.currentRegion = RegionsService.loadCurrentRegion(from: userDefaults)

        super.init()

        updateRegionsList()

        self.locationService.addDelegate(self)
    }

    // MARK: - Regions Data

    public private(set) var regions: [Region] {
        didSet {
            storeRegions()
        }
    }

    public private(set) var currentRegion: Region? {
        didSet {
            if let currentRegion = currentRegion {
                delegate?.regionsService(self, updatedRegion: currentRegion)
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
        userDefaults.set(regions, forKey: RegionsService.storedRegionsUserDefaultsKey)
        userDefaults.set(Date(), forKey: RegionsService.regionsUpdatedAtUserDefaultsKey)
    }

    private func storeCurrentRegion() {
        userDefaults.set(currentRegion, forKey: RegionsService.currentRegionUserDefaultsKey)
    }

    // MARK: - Load Stored Regions

    private class func loadStoredRegions(from userDefaults: UserDefaults) -> [Region] {
        guard let regions = userDefaults.object(forKey: storedRegionsUserDefaultsKey) as? [Region] else {
            return bundledRegions
        }

        return regions
    }

    private class func loadCurrentRegion(from userDefaults: UserDefaults) -> Region? {
        return userDefaults.object(forKey: currentRegionUserDefaultsKey) as? Region
    }

    // MARK: - Bundled Regions

    private class var bundledRegions: [Region] {
        let bundle = Bundle(for: self)
        let bundledRegionsFilePath = bundle.path(forResource: "regions-v3", ofType: "json")!
        return regionsFromDataAtPath(bundledRegionsFilePath)!
    }

    private class func regionsFromDataAtPath(_ path: String) -> [Region]? {
        do {
            let data = try NSData(contentsOfFile: path) as Data
            return try JSONDecoder().decode([Region].self, from: data)
        }
        catch {
            return nil
        }
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

    private func updateCurrentRegion() {
        guard let location = locationService.currentLocation else {
            return
        }

        guard let newRegion = (regions.filter { $0.contains(location: location) }).first else {
            delegate?.regionsServiceUnableToSelectRegion(self)
            return
        }

        currentRegion = newRegion
    }
}
