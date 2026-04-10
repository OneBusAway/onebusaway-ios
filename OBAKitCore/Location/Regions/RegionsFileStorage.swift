//
//  RegionsFileStorage.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

// MARK: - Protocol

/// Provides file-based persistence for region data.
public protocol RegionsFileStorageProtocol {
    /// Loads downloaded/server-refreshed regions from disk.
    /// Returns `nil` if no file exists yet.
    func loadDefaultRegions() throws -> [Region]?

    /// Persists downloaded/server-refreshed regions to disk.
    func saveDefaultRegions(_ regions: [Region]) throws

    /// Loads all custom (user-created) regions from disk.
    /// Throws for total-failure conditions (inaccessible directory, directory listing failure).
    /// Corrupted individual region files are logged and skipped; the rest are returned.
    func loadCustomRegions() throws -> [Region]

    /// Persists a single custom region to disk.
    /// If a file for this region already exists, it is replaced.
    func saveCustomRegion(_ region: Region) throws

    /// Removes the file for the custom region with the given identifier.
    /// If no file exists for that identifier, exits without error.
    func deleteCustomRegion(identifier: RegionIdentifier) throws
}

// MARK: - Implementation

/// File-based storage for region data.
public final class RegionsFileStorage: RegionsFileStorageProtocol {

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - URL Helpers

    private func defaultRegionsFileURL() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("Regions/default-regions.json")
    }

    private func customRegionsDirectoryURL() throws -> URL {
        let documents = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return documents.appendingPathComponent("custom-regions")
    }

    private func customRegionFileURL(identifier: RegionIdentifier) throws -> URL {
        try customRegionsDirectoryURL().appendingPathComponent("\(identifier).json")
    }

    // MARK: - Default Regions

    public func loadDefaultRegions() throws -> [Region]? {
        let url = try defaultRegionsFileURL()

        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder.RESTDecoder().decode([Region].self, from: data)
    }

    public func saveDefaultRegions(_ regions: [Region]) throws {
        let url = try defaultRegionsFileURL()
        try createDirectoryIfNeeded(for: url)
        let data = try JSONEncoder().encode(regions)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Custom Regions

    public func loadCustomRegions() throws -> [Region] {
        let directoryURL = try customRegionsDirectoryURL()

        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )

        return contents.compactMap { fileURL -> Region? in
            guard fileURL.pathExtension == "json" else { return nil }
            do {
                let data = try Data(contentsOf: fileURL)
                return try JSONDecoder.RESTDecoder().decode(Region.self, from: data)
            } catch {
                Logger.error("RegionsFileStorage: Skipping corrupted custom region file '\(fileURL.lastPathComponent)': \(error)")
                return nil
            }
        }
    }

    public func saveCustomRegion(_ region: Region) throws {
        let url = try customRegionFileURL(identifier: region.regionIdentifier)
        try createDirectoryIfNeeded(for: url)
        let data = try JSONEncoder().encode(region)
        try data.write(to: url, options: .atomic)
    }

    public func deleteCustomRegion(identifier: RegionIdentifier) throws {
        let url = try customRegionFileURL(identifier: identifier)

        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try fileManager.removeItem(at: url)
    }

    // MARK: - Private Helpers

    private func createDirectoryIfNeeded(for fileURL: URL) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}
