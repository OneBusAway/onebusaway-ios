//
//  GeohashCache.swift
//  OBAKitCore
//
//  Created by Alan Chu on 4/10/23.
//

import Foundation

public struct GeohashCacheDifference<KeyType, ElementType> {
    public enum Change<ChangeType> {
        case removal(ChangeType)
        case insertion(ChangeType)
    }

    public let keyChanges: [Change<KeyType>]
    public let elementChanges: [Change<ElementType>]

    fileprivate init(keyChanges: [Change<KeyType>], elementChanges: [Change<ElementType>]) {
        self.keyChanges = keyChanges
        self.elementChanges = elementChanges
    }
}

public struct GeohashCache<Element> {
    public var geohashes: [Geohash] {
        Array(cache.keys)
    }

    /// A flattened collection of all elements.
    public var elements: [Element] {
        Array(cache.values)
    }

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

    public func contains(geohash: Geohash) -> Bool {
        return cache.keys.contains(geohash)
    }

    @discardableResult
    public mutating func upsert(geohash: Geohash, element: Element) -> GeohashCacheDifference<Geohash, Element> {
        let geohashDiff: [GeohashCacheDifference<Geohash, Element>.Change<Geohash>]
        var elementDiff: [GeohashCacheDifference<Geohash, Element>.Change<Element>] = []

        if self.contains(geohash: geohash), let existingElement = cache[geohash] {
            geohashDiff = []
            elementDiff.append(.removal(existingElement))
        } else {
            geohashDiff = [.insertion(geohash)]
        }

        self.cache[geohash] = element
        elementDiff.append(.insertion(element))

        return GeohashCacheDifference(keyChanges: geohashDiff, elementChanges: elementDiff)
    }

    /// Removes non-active geohashes from memory.
    @discardableResult
    public mutating func discardContentIfPossible() -> GeohashCacheDifference<Geohash, Element> {
        var geohashDiff: [GeohashCacheDifference<Geohash, Element>.Change<Geohash>] = []
        var elementDiff: [GeohashCacheDifference<Geohash, Element>.Change<Element>] = []

        // TODO: Don't remove elements of neighboring active-geohashes.

        for (geohash, _) in cache where !activeGeohashes.contains(geohash) {
            if let elements = self.cache[geohash] {
                elementDiff.append(.removal(elements))
            }
            geohashDiff.append(.removal(geohash))
            self.cache[geohash] = nil
        }

        return GeohashCacheDifference(keyChanges: geohashDiff, elementChanges: elementDiff)
    }
}

// MARK: - GeohashCache.Difference.Change Equatable methods
extension GeohashCacheDifference.Change: Equatable where KeyType: Equatable, ElementType: Equatable, ChangeType: Equatable {
    public static func == (
        lhs: GeohashCacheDifference<KeyType, ElementType>.Change<ChangeType>,
        rhs: GeohashCacheDifference<KeyType, ElementType>.Change<ChangeType>
    ) -> Bool {
        switch (lhs, rhs) {
        case (.insertion(let lhsElement), .insertion(let rhsElement)):
            return lhsElement == rhsElement
        case (.removal(let lhsElement), .removal(let rhsElement)):
            return lhsElement == rhsElement
        default:
            return false
        }
    }
}
