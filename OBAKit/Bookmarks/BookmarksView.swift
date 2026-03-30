//
//  BookmarksView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore
import WidgetKit

// MARK: - Sort Mode

enum BookmarkSortMode: String {
    case byGroup   = "OBABookmarksController_SortBookmarksByGroup_group"
    case byDistance = "OBABookmarksController_SortBookmarksByGroup_distance"
}

/// No-op delegate used only during BookmarkDataLoader init before `self` is available.
private final class PlaceholderDelegate: NSObject, BookmarkDataDelegate {
    static let shared = PlaceholderDelegate()
    func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader) {}
}

// MARK: - Row model

struct BookmarkRow: Identifiable {
    let id: String          // bookmark id string
    let name: String
    let stopID: StopID
    let bookmark: Bookmark
    /// Up to 3 upcoming departures (nil = not a trip bookmark / not yet loaded)
    let departures: [DepartureInfo]?

    struct DepartureInfo: Identifiable {
        let id: String      // tripID
        let minutesText: String
        let color: UIColor
        let shouldHighlight: Bool
    }
}

// MARK: - ViewModel

@MainActor
final class BookmarksSwiftUIViewModel: NSObject, ObservableObject, BookmarkDataDelegate {
    @Published var sections: [(id: String, title: String, rows: [BookmarkRow])] = []
    @Published var sortMode: BookmarkSortMode {
        didSet {
            application.userDefaults.set(sortMode == .byGroup, forKey: sortModeKey)
            rebuildSections()
        }
    }
    @Published var isEmpty: Bool = true
    @Published var hasPendingMigration: Bool = false
    /// Sections the user has collapsed (persisted to UserDefaults).
    @Published var collapsedSections: Set<String> = []

    private let application: Application
    private let sortModeKey = "OBABookmarksController_SortBookmarksByGroup"
    private let collapsedKey = "collapsedBookmarkSections"
    private let dataLoader: BookmarkDataLoader
    private var arrivalDepartureTimes: ArrivalDepartureTimes = [:]
    private let feedbackGenerator = UISelectionFeedbackGenerator()
    private lazy var dataLoadFeedback = DataLoadFeedbackGenerator(application: application)

    init(application: Application) {
        self.application = application
        let legacyBool = application.userDefaults.bool(forKey: "OBABookmarksController_SortBookmarksByGroup")
        self.sortMode = legacyBool ? .byGroup : .byDistance
        hasPendingMigration = application.hasDataToMigrate
        self.dataLoader = BookmarkDataLoader(application: application, delegate: PlaceholderDelegate.shared)
        // Restore collapsed sections
        if let data = application.userDefaults.data(forKey: "collapsedBookmarkSections"),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            self.collapsedSections = decoded
        }
        super.init()
        dataLoader.delegate = self
    }

    func loadData() {
        dataLoader.loadData()
        rebuildSections()
    }

    func cancelUpdates() {
        dataLoader.cancelUpdates()
    }

    /// Nonisolated variant safe to call from `deinit`.
    nonisolated func cancelUpdatesSync() {
        dataLoader.cancelUpdates()
    }

    // BookmarkDataDelegate
    nonisolated func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader) {
        Task { @MainActor in
            self.rebuildSections()
            self.dataLoadFeedback.dataLoad(.success)
        }
    }

    func rebuildSections() {
        let currentRegionID = application.regionsService.currentRegion?.id
        let allBookmarks = application.userDataStore.bookmarks
            .filter { $0.regionIdentifier == currentRegionID }

        isEmpty = allBookmarks.isEmpty
        hasPendingMigration = application.hasDataToMigrate

        let sorted: [(id: String, title: String, bookmarks: [Bookmark])]

        if sortMode == .byDistance,
           let location = application.locationService.currentLocation {
            let distanceSorted = allBookmarks.sorted {
                $0.stop.location.distance(from: location) < $1.stop.location.distance(from: location)
            }
            sorted = [(
                id: "distance_sorted_group",
                title: OBALoc("bookmarks_controller.sorted_by_distance_header",
                              value: "Sorted by Distance",
                              comment: "The table section header on the bookmarks controller for when bookmarks are sorted by distance."),
                bookmarks: distanceSorted
            )]
        } else {
            var groups: [(id: String, title: String, bookmarks: [Bookmark])] = application.userDataStore.bookmarkGroups.map { group in
                (
                    id: group.id.uuidString,
                    title: group.name,
                    bookmarks: application.userDataStore.bookmarksInGroup(group)
                        .filter { $0.regionIdentifier == currentRegionID }
                )
            }
            let ungrouped = application.userDataStore.bookmarksInGroup(nil)
                .filter { $0.regionIdentifier == currentRegionID }
            if !ungrouped.isEmpty {
                groups.append((
                    id: "unknown_group",
                    title: OBALoc("bookmarks_controller.ungrouped_bookmarks_section.title",
                                  value: "Bookmarks",
                                  comment: "The title for the bookmarks controller section that shows bookmarks that aren't in a group."),
                    bookmarks: ungrouped
                ))
            }
            sorted = groups
        }

        sections = sorted.compactMap { group -> (id: String, title: String, rows: [BookmarkRow])? in
            let rows = group.bookmarks.map { bookmark -> BookmarkRow in
                var departures: [BookmarkRow.DepartureInfo]? = nil
                if let key = TripBookmarkKey(bookmark: bookmark) {
                    let arrDeps = dataLoader.dataForKey(key)
                    if !arrDeps.isEmpty {
                        departures = arrDeps.prefix(3).map { arrDep in
                            let highlight = shouldHighlight(arrivalDeparture: arrDep)
                            return BookmarkRow.DepartureInfo(
                                id: arrDep.tripID,
                                minutesText: application.formatters.shortFormattedTime(until: arrDep),
                                color: application.formatters.colorForScheduleStatus(arrDep.scheduleStatus),
                                shouldHighlight: highlight
                            )
                        }
                    }
                }
                return BookmarkRow(
                    id: bookmark.id.uuidString,
                    name: bookmark.name,
                    stopID: bookmark.stopID,
                    bookmark: bookmark,
                    departures: departures
                )
            }
            guard !rows.isEmpty else { return nil }
            return (id: group.id, title: group.title, rows: rows)
        }
    }

    private func shouldHighlight(arrivalDeparture: ArrivalDeparture) -> Bool {
        var highlight = false
        if let last = arrivalDepartureTimes[arrivalDeparture.tripID] {
            highlight = last != arrivalDeparture.arrivalDepartureMinutes
        }
        arrivalDepartureTimes[arrivalDeparture.tripID] = arrivalDeparture.arrivalDepartureMinutes
        return highlight
    }

    func toggleCollapse(sectionID: String) {
        feedbackGenerator.selectionChanged()
        if collapsedSections.contains(sectionID) {
            collapsedSections.remove(sectionID)
        } else {
            collapsedSections.insert(sectionID)
        }
        if let data = try? JSONEncoder().encode(collapsedSections) {
            application.userDefaults.set(data, forKey: collapsedKey)
        }
    }

    func delete(bookmark: Bookmark) {
        if let routeID = bookmark.routeID, let headsign = bookmark.tripHeadsign {
            application.analytics?.reportEvent(
                pageURL: "app://localhost/bookmarks",
                label: AnalyticsLabels.removeBookmark,
                value: AnalyticsLabels.addRemoveBookmarkValue(
                    routeID: routeID, headsign: headsign, stopID: bookmark.stopID))
        }
        application.userDataStore.delete(bookmark: bookmark)
        rebuildSections()
        reloadWidget()
    }

    func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: "OBAWidget")
    }
}

// MARK: - SwiftUI View

struct BookmarksView: View {
    @ObservedObject var viewModel: BookmarksSwiftUIViewModel
    var hostViewController: UIViewController?
    var application: Application?

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                bookmarksList
            }
        }
        .onAppear { viewModel.rebuildSections() }
    }

    // MARK: - List

    private var bookmarksList: some View {
        List {
            ForEach(viewModel.sections, id: \.id) { section in
                let isCollapsed = viewModel.collapsedSections.contains(section.id)
                Section {
                    if !isCollapsed {
                        ForEach(section.rows) { row in
                            bookmarkRow(row)
                        }
                    }
                } header: {
                    Button {
                        viewModel.toggleCollapse(sectionID: section.id)
                    } label: {
                        HStack {
                            Text(section.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            viewModel.loadData()
            viewModel.reloadWidget()
        }
    }

    @ViewBuilder
    private func bookmarkRow(_ row: BookmarkRow) -> some View {
        Button {
            guard let vc = hostViewController, let app = application else { return }
            app.viewRouter.navigateTo(stop: row.bookmark.stop, from: vc, bookmark: row.bookmark)
        } label: {
            BookmarkRowView(row: row)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                viewModel.delete(bookmark: row.bookmark)
            } label: {
                Label(Strings.delete, systemImage: "trash")
            }
            Button {
                showEditBookmark(row.bookmark)
            } label: {
                Label(Strings.edit, systemImage: "square.and.pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                showEditBookmark(row.bookmark)
            } label: {
                Label(Strings.edit, systemImage: "square.and.pencil")
            }
            Button(role: .destructive) {
                viewModel.delete(bookmark: row.bookmark)
            } label: {
                Label(Strings.delete, systemImage: "trash")
            }
        } preview: {
            StopPreviewRepresentable(application: application, stopID: row.stopID)
        }
        .accessibilityLabel(row.name)
        .accessibilityHint(OBALoc("voiceover.bookmarks.row_hint",
                                  value: "Tap to view stop arrivals",
                                  comment: "VoiceOver hint for bookmark rows."))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(Strings.emptyBookmarkTitle)
                .font(.title2.bold())

            Text(viewModel.hasPendingMigration
                 ? Strings.emptyBookmarkBodyWithPendingMigration
                 : Strings.emptyBookmarkBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func showEditBookmark(_ bookmark: Bookmark) {
        guard let vc = hostViewController, let app = application else { return }
        let editor = EditBookmarkViewController(
            application: app,
            stop: bookmark.stop,
            bookmark: bookmark,
            delegate: vc as? BookmarkEditorDelegate
        )
        let nav = UINavigationController(rootViewController: editor)
        app.viewRouter.present(nav, from: vc)
    }
}

// MARK: - Bookmark Row subview

private struct BookmarkRowView: View {
    let row: BookmarkRow

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            Spacer()
            if let departures = row.departures, !departures.isEmpty {
                HStack(spacing: 6) {
                    ForEach(departures) { dep in
                        Text(dep.minutesText)
                            .font(.subheadline.bold())
                            .foregroundStyle(Color(dep.color))
                    }
                }
            }
        }
    }
}

// MARK: - Stop preview for context menu

private struct StopPreviewRepresentable: UIViewControllerRepresentable {
    let application: Application?
    let stopID: StopID

    func makeUIViewController(context: Context) -> UIViewController {
        guard let app = application else { return UIViewController() }
        return StopViewController(application: app, stopID: stopID)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}


