//
//  DataMigrationResultViewModel.swift
//  OBAKit
//
//  Created by Alan Chu on 1/4/23.
//

import OBAKitCore

struct DataMigrationReportItem: Identifiable {
    let id = UUID()
    var systemImageName: String
    var title: String
    var subtitle: String?
    var error: Error?
}

struct DataMigrationReportGroup: Identifiable {
    let id = UUID()
    var title: String
    var items: [DataMigrationReportItem] = []
}

extension DataMigrator_.MigrationReport {
    func viewModel() -> [DataMigrationReportGroup] {
        var groups: [DataMigrationReportGroup] = []

        // Metadata
        var metadata = DataMigrationReportGroup(title: "Metadata")
        metadata.items.append(resultToItem(title: "User ID", result: userIDMigrationResult))
        metadata.items.append(resultToItem(title: "Region", result: regionMigrationResult))

        groups.append(metadata)

        // Recent Stops
        var recentStops = DataMigrationReportGroup(title: "Recent Stops")
        for recentStopResult in recentStopsMigrationResult {
            let title = recentStopResult.key.title
            recentStops.items.append(resultToItem(title: title, result: recentStopResult.value))
        }
        groups.append(recentStops)

        // Loose bookmarks
        var bookmarks = DataMigrationReportGroup(title: "Bookmarks")
        for bookmarkResult in bookmarksMigrationResult {
            let title = bookmarkResult.key.name
            bookmarks.items.append(resultToItem(title: title, result: bookmarkResult.value))
        }
        groups.append(bookmarks)

        // Bookmark groups, each bookmark group is its own section.
        var bookmarkGroups: [DataMigrationReportGroup] = []
        for bookmarkGroupResult in bookmarkGroupsMigrationResult {
            var groupViewModel = DataMigrationReportGroup(title: bookmarkGroupResult.key.name ?? "<unnamed group>")
            let bookmarks = bookmarkGroupResult.value.bookmarks
            for bookmark in bookmarks {
                groupViewModel.items.append(resultToItem(title: bookmark.key.name, result: bookmark.value))
            }

            bookmarkGroups.append(groupViewModel)
        }
        groups.append(contentsOf: bookmarkGroups)

        return groups
    }

    private func resultToItem<T>(title: String, subtitle: String? = nil, result: Result<T, any Error>?) -> DataMigrationReportItem {
        let systemImage: String
        let error: Error?
        switch result {
        case .success:
            systemImage = "checkmark.diamond"
            error = nil
        case .failure(let _error):
            systemImage = "xmark.diamond"
            error = _error
        case .none:             // Did not do anything.
            systemImage = "minus.diamond"
            error = nil
        }

        return .init(systemImageName: systemImage, title: title, subtitle: subtitle, error: error)
    }
}
