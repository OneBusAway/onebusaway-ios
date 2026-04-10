//
//  RegionsFileStorageTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
@testable import OBAKitCore

class RegionsFileStorageTests: XCTestCase {

    private var temporaryDirectory: URL!
    private var fileManager: FileManager!
    private var storage: RegionsFileStorage!

    override func setUp() {
        super.setUp()

        fileManager = .default
        temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        // Use a custom subclass to redirect standard system directories to the temp directory.
        storage = RegionsFileStorage(fileManager: TemporaryDirectoryFileManager(temporaryDirectory: temporaryDirectory))
    }

    override func tearDown() {
        try? fileManager.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    // MARK: - Default Regions

    func test_loadDefaultRegions_returnsNilWhenNoFileExists() throws {
        let result = try storage.loadDefaultRegions()
        XCTAssertNil(result, "Expected nil when no default regions file has been written")
    }

    func test_saveAndLoadDefaultRegions_roundTrip() throws {
        let regions = [Fixtures.customMinneapolisRegion]
        try storage.saveDefaultRegions(regions)

        let loaded = try XCTUnwrap(storage.loadDefaultRegions())
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, regions.first?.name)
        XCTAssertEqual(loaded.first?.regionIdentifier, regions.first?.regionIdentifier)
    }

    func test_saveDefaultRegions_overwritesPreviousFile() throws {
        let first = [Fixtures.customMinneapolisRegion]
        try storage.saveDefaultRegions(first)

        let second = try XCTUnwrap(Fixtures.loadSomeRegions()).prefix(1).map { $0 }
        try storage.saveDefaultRegions(second)

        let loaded = try XCTUnwrap(storage.loadDefaultRegions())
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, second.first?.name)
    }

    func test_saveDefaultRegions_createsIntermediateDirectories() throws {
        // The storage should auto-create any missing parent directories.
        let regions = [Fixtures.customMinneapolisRegion]
        XCTAssertNoThrow(try storage.saveDefaultRegions(regions))
        let loaded = try storage.loadDefaultRegions()
        XCTAssertNotNil(loaded)
    }

    // MARK: - Custom Regions

    func test_loadCustomRegions_returnsEmptyWhenNoFilesExist() throws {
        let result = try storage.loadCustomRegions()
        XCTAssertTrue(result.isEmpty, "Expected empty array when no custom region files exist")
    }

    func test_saveAndLoadCustomRegion_roundTrip() throws {
        let region = Fixtures.customMinneapolisRegion
        try storage.saveCustomRegion(region)

        let loaded = try storage.loadCustomRegions()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, region.name)
        XCTAssertEqual(loaded.first?.regionIdentifier, region.regionIdentifier)
    }

    func test_saveCustomRegion_replacesExistingRegionWithSameIdentifier() throws {
        let region = Fixtures.customMinneapolisRegion
        try storage.saveCustomRegion(region)
        XCTAssertEqual(try storage.loadCustomRegions().count, 1)

        // Saving the same region again should overwrite the existing file, not create a second one.
        try storage.saveCustomRegion(region)

        XCTAssertEqual(try storage.loadCustomRegions().count, 1, "Expected saving the same region twice to result in a single file")
    }

    func test_deleteCustomRegion_removesFile() throws {
        let region = Fixtures.customMinneapolisRegion
        try storage.saveCustomRegion(region)
        XCTAssertEqual(try storage.loadCustomRegions().count, 1)

        try storage.deleteCustomRegion(identifier: region.regionIdentifier)
        XCTAssertTrue(try storage.loadCustomRegions().isEmpty, "Expected custom regions to be empty after deletion")
    }

    func test_deleteCustomRegion_doesNotThrowWhenFileDoesNotExist() {
        XCTAssertNoThrow(try storage.deleteCustomRegion(identifier: 9999))
    }

    func test_loadCustomRegions_skipsCorruptedFiles() throws {
        // Write a valid region and a corrupted JSON file side by side.
        let validRegion = Fixtures.customMinneapolisRegion
        try storage.saveCustomRegion(validRegion)

        // Manually write a corrupted JSON file into the custom-regions directory.
        let corruptedFileURL = try customRegionsDirectoryURL().appendingPathComponent("corrupted.json")
        try "{ this is not valid JSON }".write(to: corruptedFileURL, atomically: true, encoding: .utf8)

        // loadCustomRegions must not throw when individual files are corrupted — it skips them and returns the rest.
        let loaded = try storage.loadCustomRegions()
        XCTAssertEqual(loaded.count, 1, "Expected corrupted file to be skipped; only valid region should be returned")
        XCTAssertEqual(loaded.first?.name, validRegion.name)
    }

    // MARK: - Helpers

    private func customRegionsDirectoryURL() throws -> URL {
        temporaryDirectory.appendingPathComponent("Documents/custom-regions")
    }
}

// MARK: - TemporaryDirectoryFileManager

/// A `FileManager` subclass that redirects Application Support and Documents
/// directory lookups to a temporary directory so tests never touch the real file system.
private class TemporaryDirectoryFileManager: FileManager {

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
