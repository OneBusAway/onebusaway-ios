//
//  MockRegionsFileStorage.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
@testable import OBAKitCore

class MockRegionsFileStorage: RegionsFileStorageProtocol {
    var storedDefaultRegions: [Region]?
    var storedCustomRegions: [Region] = []
    var loadDefaultRegionsError: Error?
    var saveDefaultRegionsError: Error?
    var loadCustomRegionsError: Error?
    var saveCustomRegionError: Error?
    var deleteCustomRegionError: Error?

    init(defaultRegions: [Region]? = nil) {
        storedDefaultRegions = defaultRegions
    }

    func loadDefaultRegions() throws -> [Region]? {
        if let error = loadDefaultRegionsError { throw error }
        return storedDefaultRegions
    }

    func saveDefaultRegions(_ regions: [Region]) throws {
        if let error = saveDefaultRegionsError { throw error }
        storedDefaultRegions = regions
    }

    func loadCustomRegions() throws -> [Region] {
        if let error = loadCustomRegionsError { throw error }
        return storedCustomRegions
    }

    func saveCustomRegion(_ region: Region) throws {
        if let error = saveCustomRegionError { throw error }
        storedCustomRegions.removeAll { $0.regionIdentifier == region.regionIdentifier }
        storedCustomRegions.append(region)
    }

    func deleteCustomRegion(identifier: RegionIdentifier) throws {
        if let error = deleteCustomRegionError { throw error }
        storedCustomRegions.removeAll { $0.regionIdentifier == identifier }
    }
}
