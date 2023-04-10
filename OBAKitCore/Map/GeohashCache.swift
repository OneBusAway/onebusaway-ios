//
//  GeohashCache.swift
//  OBAKitCore
//
//  Created by Alan Chu on 4/10/23.
//

import Foundation

public struct GeohashCache<Element> {
    public var activeGeohashes: Set<Geohash> = []
    private var cache: [Geohash: Element] = [:]

    public subscript(_ geohash: Geohash) -> Element? {
        get {
            return cache[geohash]
        }
        set {
            cache[geohash] = newValue
        }
    }

    public init() {
        self.activeGeohashes = []
        self.cache = [:]
    }

    /// Removes non-active geohashes from memory.
    public mutating func discardContentIfPossible() {
        for (geohash, _) in cache where !activeGeohashes.contains(geohash) {
            self.cache[geohash] = nil
        }
    }
}
