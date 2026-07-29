//
//  RegionsFileStorageTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class RegionsFileStorageTests {

    private var temporaryDirectory: URL!
    private var fileManager: FileManager!
    private var storage: RegionsFileStorage!

    init() {
        fileManager = .default
        temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        // Use a custom subclass to redirect standard system directories to the temp directory.
        storage = RegionsFileStorage(fileManager: TemporaryDirectoryFileManager(temporaryDirectory: temporaryDirectory))
    }

    isolated deinit {
        try? fileManager.removeItem(at: temporaryDirectory)
    }

    // MARK: - Default Regions

    @Test func `Load default regions returns nil when no file exists`() throws {
        let result = try storage.loadDefaultRegions()
        #expect(result == nil, "Expected nil when no default regions file has been written")
    }

    @Test func `Save and load default regions round trip`() throws {
        let regions = [Fixtures.customMinneapolisRegion]
        try storage.saveDefaultRegions(regions)

        let loaded = try #require(try storage.loadDefaultRegions())
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == regions.first?.name)
        #expect(loaded.first?.regionIdentifier == regions.first?.regionIdentifier)
    }

    @Test func `Save default regions overwrites previous file`() throws {
        let first = [Fixtures.customMinneapolisRegion]
        try storage.saveDefaultRegions(first)

        let second = try Fixtures.loadSomeRegions().prefix(1).map { $0 }
        try storage.saveDefaultRegions(second)

        let loaded = try #require(try storage.loadDefaultRegions())
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == second.first?.name)
    }

    @Test func `Save default regions creates intermediate directories`() throws {
        // The storage should auto-create any missing parent directories.
        let regions = [Fixtures.customMinneapolisRegion]
        #expect(throws: Never.self) { try storage.saveDefaultRegions(regions) }
        let loaded = try storage.loadDefaultRegions()
        #expect(loaded != nil)
    }

    // MARK: - Custom Regions

    @Test func `Load custom regions returns empty when no files exist`() throws {
        let result = try storage.loadCustomRegions()
        #expect(result.isEmpty, "Expected empty array when no custom region files exist")
    }

    @Test func `Save and load custom region round trip`() throws {
        let region = Fixtures.customMinneapolisRegion
        try storage.saveCustomRegion(region)

        let loaded = try storage.loadCustomRegions()
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == region.name)
        #expect(loaded.first?.regionIdentifier == region.regionIdentifier)
    }

    @Test func `Save custom region replaces existing region with same identifier`() throws {
        let region = Fixtures.customMinneapolisRegion
        try storage.saveCustomRegion(region)
        #expect(try storage.loadCustomRegions().count == 1)

        // Saving the same region again should overwrite the existing file, not create a second one.
        try storage.saveCustomRegion(region)

        #expect(try storage.loadCustomRegions().count == 1, "Expected saving the same region twice to result in a single file")
    }

    @Test func `Delete custom region removes file`() throws {
        let region = Fixtures.customMinneapolisRegion
        try storage.saveCustomRegion(region)
        #expect(try storage.loadCustomRegions().count == 1)

        try storage.deleteCustomRegion(identifier: region.regionIdentifier)
        #expect(try storage.loadCustomRegions().isEmpty, "Expected custom regions to be empty after deletion")
    }

    @Test func `Delete custom region does not throw when file does not exist`() {
        #expect(throws: Never.self) { try storage.deleteCustomRegion(identifier: 9999) }
    }

    @Test func `Load custom regions skips corrupted files`() throws {
        // Write a valid region and a corrupted JSON file side by side.
        let validRegion = Fixtures.customMinneapolisRegion
        try storage.saveCustomRegion(validRegion)

        // Manually write a corrupted JSON file into the custom-regions directory.
        let corruptedFileURL = try customRegionsDirectoryURL().appendingPathComponent("corrupted.json")
        try "{ this is not valid JSON }".write(to: corruptedFileURL, atomically: true, encoding: .utf8)

        // loadCustomRegions must not throw when individual files are corrupted — it skips them and returns the rest.
        let loaded = try storage.loadCustomRegions()
        #expect(loaded.count == 1, "Expected corrupted file to be skipped; only valid region should be returned")
        #expect(loaded.first?.name == validRegion.name)
    }

    // MARK: - Helpers

    private func customRegionsDirectoryURL() throws -> URL {
        temporaryDirectory.appendingPathComponent("Documents/custom-regions")
    }
}

// MARK: - TemporaryDirectoryFileManager

/// A `FileManager` subclass that redirects Application Support and Documents
/// directory lookups to a temporary directory so tests never touch the real file system.
// `nonisolated`: overrides nonisolated FileManager members, which the target's
// main-actor default isolation would conflict with.
private nonisolated class TemporaryDirectoryFileManager: FileManager {

    private let baseURL: URL

    init(temporaryDirectory: URL) {
        self.baseURL = temporaryDirectory
        super.init()
    }

    override func url(
        for directory: FileManager.SearchPathDirectory,
        in domain: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?,
        create shouldCreate: Bool
    ) throws -> URL {
        let subdirectory: String
        switch directory {
        case .applicationSupportDirectory:
            subdirectory = "ApplicationSupport"
        case .documentDirectory:
            subdirectory = "Documents"
        default:
            return try super.url(for: directory, in: domain, appropriateFor: url, create: shouldCreate)
        }

        let result = baseURL.appendingPathComponent(subdirectory)
        if shouldCreate && !fileExists(atPath: result.path) {
            try createDirectory(at: result, withIntermediateDirectories: true)
        }
        return result
    }
}
