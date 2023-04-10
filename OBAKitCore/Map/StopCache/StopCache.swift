//
//  StopCache.swift
//  OBAKitCore
//
//  Created by Alan Chu on 4/3/23.
//

import os.log
import MapKit
import Foundation
import GeohashKit

public protocol RESTAPIServiceProviding: AnyObject {
    var apiService: RESTAPIService? { get }
}

public protocol StopCacheDelegate: AnyObject {
    func cacheDidUpdate(_ cache: StopCache, difference: GeohashCacheDifference<Geohash, StopCache.Entry>) async
}

public actor StopCache {
    // MARK: - Structs and such
    public static let DefaultGeohashPrecision = 6  // Geohash precision of 6 yields cells of approximately 1.22x0.61km
    static let DefaultExpirationInMinutes = 60

    static private var ExpirationTimeIntervalFromNow: TimeInterval {
        return TimeInterval(DefaultExpirationInMinutes) * 60
    }

    public struct Entry: Identifiable {
        public let id: String      // AKA the geohash
        public let stops: [Stop]
        public let createdAt: Date

        init(geohash: Geohash.Hash, apiResponse: RESTAPIResponse<[Stop]>) {
            self.id = geohash
            self.stops = apiResponse.list
            self.createdAt = Date()
        }
    }

    // MARK: - Properties
    public weak var apiServiceProvider: RESTAPIServiceProviding?
    public weak var delegate: StopCacheDelegate?

    private let logger: os.Logger

    /// Computed stops.
    public var stops: [Stop] {
        return cache.elements.flatMap(\.stops)
    }
    private var cache: GeohashCache<Entry>

    public init(apiServiceProvider: RESTAPIServiceProviding, delegate: StopCacheDelegate? = nil) {
        self.apiServiceProvider = apiServiceProvider
        self.cache = GeohashCache()
        self.delegate = delegate

        self.logger = os.Logger(subsystem: "org.onebusaway.iphone", category: "StopCache")
    }

    nonisolated public func loadStops(for geohash: Geohash) async throws {
        let loggingID = UUID()
        func logTrace(_ message: String) {
            logger.trace("[\(loggingID)] - [\(geohash.geohash)]: \(message)")
        }

        logTrace("Load stops begin")

        defer {
            logTrace("Load stops finished")
        }

        // Check if an existing entry exists, and is not expired.
        if let existingEntry = await cache[geohash] {
            logTrace("Cache hit")

            guard existingEntry.createdAt.distance(to: .now) >= Self.ExpirationTimeIntervalFromNow else {
                logTrace("Cache still fresh")
                return
            }

            logTrace("Cache stale")
        } else {
            logTrace("Cache miss")
        }

        guard let apiService = await apiServiceProvider?.apiService else {
            throw UnstructuredError("No API service available")
        }

        let apiResponse = try await apiService.getStops(region: geohash.region)
        let entry = Entry(geohash: geohash.geohash, apiResponse: apiResponse)

        if let limitExceeded = apiResponse.limitExceeded, limitExceeded {
            fatalError("limit exceeded")    // TODO: Gracefully handle this by increasing Geohash precision (smaller tiles)
        }

        await updateCache(key: geohash, value: entry)
    }

    // MARK: - Mutations
    /// Actor-enforced access.
    private func updateCache(key: Geohash, value: Entry) async {
        let diff = self.cache.upsert(geohash: key, element: value)

        if let delegate {
            await delegate.cacheDidUpdate(self, difference: diff)
        }
    }

    public func discardContentsIfPossible() {
        logger.trace("Discarding content... (current size: \(self.cache.elements.count))")
        let diff = self.cache.discardContentIfPossible()
        if let delegate {
            Task { @MainActor in
                await delegate.cacheDidUpdate(self, difference: diff)
            }
        }
        logger.trace("Finished discarding content. (new size: \(self.cache.elements.count))")
    }

    /// - precondition: All elements of `geohashes` must have the same precision as ``DefaultGeohashPrecision``.
    public func setActiveGeohashes(_ geohashes: Set<Geohash>) {
        #if DEBUG
        let illegalGeohashes = geohashes.filter { geohash in
            geohash.precision != Self.DefaultGeohashPrecision
        }

        guard illegalGeohashes.isEmpty else {
            preconditionFailure("Geohash precision mismatch: \(illegalGeohashes).")
        }
        #endif

        logger.trace("New active geohash(es): \(geohashes)")
        self.cache.activeGeohashes = geohashes
    }
}
