//
//  DataMigrationReportViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Stands in for the legacy app's archived classes, which only decode. Unlike the
/// fixed-value dummies in `MigrationModelTests`, it encodes whatever it's given,
/// so one report can hold several distinctly named stops, bookmarks and groups.
@objc(DataMigrationReportTestsArchivedValues) private class ArchivedValues: NSObject, NSCoding {
    let values: [String: Any]

    init(_ values: [String: Any]) {
        self.values = values
        super.init()
    }

    func encode(with coder: NSCoder) {
        for (key, value) in values {
            // MigrationRecentStop reads its coordinate with decodeDouble.
            if let double = value as? Double {
                coder.encode(double, forKey: key)
            } else {
                coder.encode(value, forKey: key)
            }
        }
    }

    required init?(coder: NSCoder) { nil }
}

@objc(DataMigrationReportTestsRecentStop) private final class ArchivedRecentStop: ArchivedValues {}
@objc(DataMigrationReportTestsBookmark) private final class ArchivedBookmark: ArchivedValues {}
@objc(DataMigrationReportTestsBookmarkGroup) private final class ArchivedBookmarkGroup: ArchivedValues {}

/// Tests for `DataMigrator.MigrationReport.viewModel()`, which turns a migration
/// report into the grouped list the migration screen shows.
///
/// The report holds its results in dictionaries, so the order of items inside a
/// group, and of the bookmark groups themselves, is unspecified. The tests compare
/// those as sets.
@MainActor
@Suite(.serialized)
final class DataMigrationReportViewModelTests {

    private struct MigrationFailure: Error, Equatable {
        let reason: String
    }

    // MARK: - Builders

    private func unarchive<T>(_ object: ArchivedValues, as type: T.Type) throws -> T {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("MigrationRecentStop", for: ArchivedRecentStop.self)
        archiver.setClassName("MigrationBookmark", for: ArchivedBookmark.self)
        archiver.setClassName("MigrationBookmarkGroup", for: ArchivedBookmarkGroup.self)
        archiver.encode(object, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()

        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(MigrationRecentStop.self, forClassName: "MigrationRecentStop")
        unarchiver.setClass(MigrationBookmark.self, forClassName: "MigrationBookmark")
        unarchiver.setClass(MigrationBookmarkGroup.self, forClassName: "MigrationBookmarkGroup")
        return try #require(unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? T)
    }

    private func recentStop(titled title: String) throws -> MigrationRecentStop {
        try unarchive(ArchivedRecentStop([
            "title": title,
            "subtitle": "Bound for Downtown",
            "stopID": "1_\(title)",
            "latitude": 47.6,
            "longitude": -122.3
        ]), as: MigrationRecentStop.self)
    }

    private func archivedBookmark(named name: String) -> ArchivedBookmark {
        ArchivedBookmark(["name": name, "stopId": "1_100", "routeShortName": "10", "tripHeadsign": "Downtown"])
    }

    private func bookmark(named name: String) throws -> MigrationBookmark {
        try unarchive(archivedBookmark(named: name), as: MigrationBookmark.self)
    }

    /// A `nil` name is archived as `NSNull`: the group must still contain a value
    /// for the key to decode at all.
    private func bookmarkGroup(named name: String?, bookmarks: [String] = []) throws -> MigrationBookmarkGroup {
        try unarchive(ArchivedBookmarkGroup([
            "name": name ?? NSNull(),
            "UUID": UUID().uuidString,
            "bookmarks": bookmarks.map(archivedBookmark(named:))
        ]), as: MigrationBookmarkGroup.self)
    }

    private func groupResult(_ group: MigrationBookmarkGroup, outcome: Result<Bookmark, Error>) -> DataMigrator.MigrationBookmarkGroupResult {
        DataMigrator.MigrationBookmarkGroupResult(
            bookmarkGroup: group,
            bookmarks: Dictionary(uniqueKeysWithValues: group.bookmarks.map { ($0, outcome) })
        )
    }

    private func migratedBookmark() throws -> Bookmark {
        Bookmark(name: "Migrated", regionIdentifier: 1, stop: try #require(Fixtures.loadSomeStops().first))
    }

    private func item(_ title: String, in group: DataMigrationReportGroup) throws -> DataMigrationReportItem {
        try #require(group.items.first { $0.title == title }, "No item titled \(title) in \(group.title)")
    }

    // MARK: - Groups

    @Test func `Groups are metadata, recent stops and bookmarks, then one per bookmark group`() throws {
        var report = DataMigrator.MigrationReport(dateStarted: Date())
        for name in ["Work", "Errands"] {
            let group = try bookmarkGroup(named: name)
            report.bookmarkGroupsMigrationResult[group] = groupResult(group, outcome: .success(try migratedBookmark()))
        }

        let titles = report.viewModel().map(\.title)

        #expect(titles.count == 5)
        #expect(Array(titles.prefix(3)) == ["Metadata", "Recent Stops", "Bookmarks"])
        #expect(Set(titles.dropFirst(3)) == ["Work", "Errands"])
    }

    // MARK: - Outcomes

    @Test func `Metadata shows a checkmark for a step that succeeded and an X with the error for one that failed`() throws {
        var report = DataMigrator.MigrationReport(dateStarted: Date())
        report.userIDMigrationResult = .success(())
        report.regionMigrationResult = .failure(MigrationFailure(reason: "region gone"))

        let metadata = try #require(report.viewModel().first)
        #expect(metadata.items.map(\.title) == ["User ID", "Region"])

        let userID = metadata.items[0]
        #expect(userID.systemImageName == "checkmark.diamond")
        #expect(userID.error == nil)

        let region = metadata.items[1]
        #expect(region.systemImageName == "xmark.diamond")
        #expect(region.error as? MigrationFailure == MigrationFailure(reason: "region gone"))
    }

    @Test func `Metadata shows a minus for steps that never ran`() throws {
        let report = DataMigrator.MigrationReport(dateStarted: Date())

        let metadata = try #require(report.viewModel().first)

        #expect(metadata.items.map(\.systemImageName) == ["minus.diamond", "minus.diamond"])
        #expect(metadata.items.allSatisfy { $0.error == nil })
    }

    // MARK: - Item titles

    @Test func `Recent stops are titled by stop and bookmarks by name, each with its own outcome`() throws {
        var report = DataMigrator.MigrationReport(dateStarted: Date())
        let stop = try #require(Fixtures.loadSomeStops().first)
        report.recentStopsMigrationResult[try recentStop(titled: "Pine St")] = .success(stop)
        report.recentStopsMigrationResult[try recentStop(titled: "3rd Ave")] = .failure(MigrationFailure(reason: "stop removed"))
        report.bookmarksMigrationResult[try bookmark(named: "Home")] = .success(try migratedBookmark())

        let groups = report.viewModel()
        let recentStops = groups[1], bookmarks = groups[2]

        #expect(Set(recentStops.items.map(\.title)) == ["Pine St", "3rd Ave"])
        #expect(try item("Pine St", in: recentStops).systemImageName == "checkmark.diamond")
        let failed = try item("3rd Ave", in: recentStops)
        #expect(failed.systemImageName == "xmark.diamond")
        #expect(failed.error as? MigrationFailure == MigrationFailure(reason: "stop removed"))

        #expect(bookmarks.items.map(\.title) == ["Home"])
        #expect(bookmarks.items.first?.systemImageName == "checkmark.diamond")
    }

    @Test func `A bookmark group without a name is titled unnamed group and lists its bookmarks`() throws {
        var report = DataMigrator.MigrationReport(dateStarted: Date())
        let group = try bookmarkGroup(named: nil, bookmarks: ["Gym", "Library"])
        #expect(group.name == nil)
        report.bookmarkGroupsMigrationResult[group] = groupResult(group, outcome: .success(try migratedBookmark()))

        let unnamed = try #require(report.viewModel().last)

        #expect(unnamed.title == "<unnamed group>")
        #expect(Set(unnamed.items.map(\.title)) == ["Gym", "Library"])
        #expect(unnamed.items.allSatisfy { $0.systemImageName == "checkmark.diamond" })
    }
}
