//
//  DataMigrationResultViewModel.swift
//  OBAKit
//
//  Created by Alan Chu on 1/4/23.
//

import OBAKitCore

struct DataMigrationResultItem: Identifiable {
    let id = UUID()
    var systemImageName: String
    var title: String
    var subtitle: String?
    var error: Error?
}

struct DataMigrationResultGroupViewModel: Identifiable {
    let id = UUID()

    // If any of the items have an error, return false.
    var overallSuccessful: Bool {
        for item in items where item.error != nil {
            return false
        }

        return true
    }

    var title: String
    var items: [DataMigrationResultItem] = []
}

extension DataMigrator_.MigrationReport {
    func viewModel() -> [DataMigrationResultGroupViewModel] {
        var groups: [DataMigrationResultGroupViewModel] = []

        // Metadata
        var metadata = DataMigrationResultGroupViewModel(title: "Metadata")
        metadata.items.append(resultToItem(title: "User ID", result: userIDMigrationResult))
        metadata.items.append(resultToItem(title: "Region", result: regionMigrationResult))

        groups.append(metadata)

        // Recent Stops
        var recentStops = DataMigrationResultGroupViewModel(title: "Recent Stops")
        for recentStopResult in recentStopsMigrationResult {
            let title = recentStopResult.key.title
            recentStops.items.append(resultToItem(title: title, result: recentStopResult.value))
        }
        groups.append(recentStops)

        // Loose bookmarks
        var bookmarks = DataMigrationResultGroupViewModel(title: "Bookmarks")
        for bookmarkResult in bookmarksMigrationResult {
            let title = bookmarkResult.key.name
            bookmarks.items.append(resultToItem(title: title, result: bookmarkResult.value))
        }
        groups.append(bookmarks)

        // Bookmark groups, each bookmark group is its own section.
        var bookmarkGroups: [DataMigrationResultGroupViewModel] = []
        for bookmarkGroupResult in bookmarkGroupsMigrationResult {
            var groupViewModel = DataMigrationResultGroupViewModel(title: bookmarkGroupResult.key.name ?? "<unnamed group>")
            let bookmarks = bookmarkGroupResult.value.bookmarks
            for bookmark in bookmarks {
                groupViewModel.items.append(resultToItem(title: bookmark.key.name, result: bookmark.value))
            }

            bookmarkGroups.append(groupViewModel)
        }
        groups.append(contentsOf: bookmarkGroups)

        return groups
    }

    private func resultToItem<T>(title: String, subtitle: String? = nil, result: Result<T, any Error>?) -> DataMigrationResultItem {
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

        return DataMigrationResultItem(systemImageName: systemImage, title: title, subtitle: subtitle, error: error)
    }
}
