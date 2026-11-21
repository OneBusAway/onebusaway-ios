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
public protocol RegionsFileStorageProtocol: Sendable {
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
public final class RegionsFileStorage: RegionsFileStorageProtocol, @unchecked Sendable {

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

        guard let data = try coordinateRead(from: url), !data.isEmpty else {
            Logger.error("RegionsFileStorage: default-regions.json is empty")
            return nil
        }

        do {
            return try JSONDecoder.RESTDecoder().decode([Region].self, from: data)
        } catch {
            if let response = try? JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[Region]>.self, from: data) {
                return response.list
            }
            Logger.error("RegionsFileStorage: Failed to decode default-regions.json: \(error)")
            throw error
        }
    }

    public func saveDefaultRegions(_ regions: [Region]) throws {
        let url = try defaultRegionsFileURL()
        try createDirectoryIfNeeded(for: url)
        let data = try JSONEncoder.RESTEncoder().encode(regions)
        try coordinateWrite(to: url, data: data)
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
                guard let data = try coordinateRead(from: fileURL), !data.isEmpty else {
                    Logger.error("RegionsFileStorage: Custom region file '\(fileURL.lastPathComponent)' is empty")
                    return nil
                }
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
        let data = try JSONEncoder.RESTEncoder().encode(region)
        try coordinateWrite(to: url, data: data)
    }

    public func deleteCustomRegion(identifier: RegionIdentifier) throws {
        let url = try customRegionFileURL(identifier: identifier)

        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try coordinateDelete(at: url)
    }

    // MARK: - File Coordination Helpers

    private func coordinateWrite(to fileURL: URL, data: Data) throws {
        var coordinatorError: NSError?
        var writeError: Error?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { targetURL in
            do {
                try data.write(to: targetURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let error = writeError ?? coordinatorError {
            throw error
        }
    }

    private func coordinateRead(from fileURL: URL) throws -> Data? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        var coordinatorError: NSError?
        var readData: Data?
        var readError: Error?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordinatorError) { targetURL in
            do {
                readData = try Data(contentsOf: targetURL)
            } catch {
                readError = error
            }
        }

        if let error = readError ?? coordinatorError {
            throw error
        }
        return readData
    }

    private func coordinateDelete(at fileURL: URL) throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        var coordinatorError: NSError?
        var deleteError: Error?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: fileURL, options: .forDeleting, error: &coordinatorError) { targetURL in
            do {
                try fileManager.removeItem(at: targetURL)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                return
            } catch {
                deleteError = error
            }
        }

        if let error = deleteError ?? coordinatorError {
            throw error
        }
    }

    // MARK: - Private Helpers

    private func createDirectoryIfNeeded(for fileURL: URL) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        guard !fileManager.fileExists(atPath: directoryURL.path) else { return }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}
