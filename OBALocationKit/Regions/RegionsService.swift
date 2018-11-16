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

@objc(OBARegionsService)
public class RegionsService: NSObject {
    private let modelService: RegionsModelService
    private let locationService: LocationService

    public init(modelService: RegionsModelService, locationService: LocationService) {
        self.modelService = modelService
        self.locationService = locationService

        regions = RegionsService.loadStoredRegions()

        super.init()

        self.locationService.addDelegate(self)
    }

    // MARK: - Regions Data

    public private(set) var regions: [Region]

    public private(set) var currentRegion: Region? {
        didSet {
            //
        }
    }
}

// MARK: - Regions Data Storage
extension RegionsService {
    private class func loadStoredRegions() -> [Region] {
        return []
    }
}

// MARK: - Region Updates
extension RegionsService: LocationServiceDelegate {
    public func locationService(_ service: LocationService, locationChanged location: CLLocation) {
        updateCurrentRegion(location: location)
    }

    private func updateCurrentRegion(location: CLLocation) {

    }

//    - (NSArray<OBARegionV2*>*)regionsWithin100Miles {
//    if (self.regions.count == 0) {
//    return @[];
//    }
//
//    CLLocation *currentLocation = self.locationManager.currentLocation;
//
//    if (!currentLocation) {
//    return @[];
//    }
//
//    return [[self.regions sortedArrayUsingComparator:^NSComparisonResult(OBARegionV2 *r1, OBARegionV2 *r2) {
//    CLLocationDistance distance1 = [r1 distanceFromLocation:currentLocation];
//    CLLocationDistance distance2 = [r2 distanceFromLocation:currentLocation];
//
//    if (distance1 > distance2) {
//    return NSOrderedDescending;
//    }
//    else if (distance1 < distance2) {
//    return NSOrderedAscending;
//    }
//    else {
//    return NSOrderedSame;
//    }
//    }] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(OBARegionV2 *r, NSDictionary<NSString *,id> *bindings) {
//    return ([r distanceFromLocation:currentLocation] < 160934); // == 100 miles
//    }]];
//    }
}
