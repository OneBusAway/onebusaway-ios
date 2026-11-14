//
//  ResolvedRegionStore.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The app's current `Region`, stored whole in a `UserDefaults` suite.
///
/// `RegionsService` deliberately persists only the region's *identifier* and
/// resolves it on read. That is right inside one process and wrong across two:
/// custom regions live in the app's own Documents directory, which a widget
/// extension cannot see, so the extension resolves the identifier to nothing.
/// The app writes the resolved region here (see `ResolvedRegionPersister`);
/// extensions read it and never write.
public struct ResolvedRegionStore {
    public static let defaultsKey = "OBAResolvedCurrentRegion"

    public let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    /// Stores `region`, or clears the stored value when it is nil.
    public func write(_ region: Region?) {
        guard let region else {
            userDefaults.removeObject(forKey: Self.defaultsKey)
            return
        }

        do {
            userDefaults.set(try PropertyListEncoder().encode(region), forKey: Self.defaultsKey)
        } catch {
            Logger.error("ResolvedRegionStore: failed to encode region \(region.regionIdentifier): \(error)")
        }
    }

    /// Directly decodes the cached resolved region from `UserDefaults`, without falling back to bundled regions.
    public var storedRegion: Region? {
        guard let data = userDefaults.data(forKey: Self.defaultsKey) else { return nil }
        return try? PropertyListDecoder().decode(Region.self, from: data)
    }

    /// The stored region. When nothing usable is stored — the app has not
    /// launched since this shipped, or the value is corrupt — falls back to
    /// looking the stored *identifier* up in the bundled regions file, which
    /// covers every region except a custom one.
    public func region(bundledRegionsFilePath: String? = nil) -> Region? {
        let storedIdentifier = userDefaults.object(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey) as? Int

        if let data = userDefaults.data(forKey: Self.defaultsKey) {
            do {
                let decoded = try PropertyListDecoder().decode(Region.self, from: data)
                if let storedIdentifier {
                    if decoded.regionIdentifier == storedIdentifier {
                        return decoded
                    }
                    Logger.error("ResolvedRegionStore: stored region \(decoded.regionIdentifier) does not match selected identifier \(storedIdentifier), falling back")
                } else {
                    return decoded
                }
            } catch {
                Logger.error("ResolvedRegionStore: stored region is unreadable, falling back: \(error)")
            }
        }

        guard
            let identifier = storedIdentifier,
            let path = bundledRegionsFilePath,
            let data = FileManager.default.contents(atPath: path)
        else {
            return nil
        }

        if let response = try? JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[Region]>.self, from: data) {
            return response.list.first { $0.regionIdentifier == identifier }
        } else if let list = try? JSONDecoder.RESTDecoder().decode([Region].self, from: data) {
            return list.first { $0.regionIdentifier == identifier }
        } else {
            return nil
        }
    }
}
