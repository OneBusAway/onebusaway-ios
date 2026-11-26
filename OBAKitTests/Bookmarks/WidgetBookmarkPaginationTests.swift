//
//  WidgetBookmarkPaginationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
struct WidgetBookmarkPaginationTests {
    private func makeIsolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "WidgetBookmarkPaginationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    // MARK: - Page Calculation & Slicing

    @Test func `Total pages handles empty, single-page, and multi-page bookmark counts`() {
        #expect(WidgetBookmarkPaginator.totalPages(bookmarkCount: 0) == 0)
        #expect(WidgetBookmarkPaginator.totalPages(bookmarkCount: -2) == 0)
        #expect(WidgetBookmarkPaginator.totalPages(bookmarkCount: 1) == 1)
        #expect(WidgetBookmarkPaginator.totalPages(bookmarkCount: 2) == 1)
        #expect(WidgetBookmarkPaginator.totalPages(bookmarkCount: 3) == 2)
        #expect(WidgetBookmarkPaginator.totalPages(bookmarkCount: 4) == 2)
        #expect(WidgetBookmarkPaginator.totalPages(bookmarkCount: 5) == 3)
        #expect(WidgetBookmarkPaginator.totalPages(bookmarkCount: 6) == 3)
        #expect(WidgetBookmarkPaginator.totalPages(bookmarkCount: 5, pageSize: 0) == 0)
    }

    @Test func `Page slice returns two bookmarks per page and partial final page`() {
        let bookmarks = ["A", "B", "C", "D", "E"]

        #expect(WidgetBookmarkPaginator.pageSlice(bookmarks: bookmarks, pageIndex: 0) == ["A", "B"])
        #expect(WidgetBookmarkPaginator.pageSlice(bookmarks: bookmarks, pageIndex: 1) == ["C", "D"])
        #expect(WidgetBookmarkPaginator.pageSlice(bookmarks: bookmarks, pageIndex: 2) == ["E"])
        #expect(WidgetBookmarkPaginator.pageSlice(bookmarks: bookmarks, pageIndex: 99) == ["E"])
        #expect(WidgetBookmarkPaginator.pageSlice(bookmarks: bookmarks, pageIndex: -1) == ["A", "B"])
        #expect(WidgetBookmarkPaginator.pageSlice(bookmarks: [String](), pageIndex: 0).isEmpty)
    }

    // MARK: - Bounds & Wrap-Around

    @Test func `Increment and decrement navigate through first, middle, and last pages`() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let paginator = WidgetBookmarkPaginator(userDefaults: defaults)

        #expect(paginator.currentPage(bookmarkCount: 6) == 0)

        let step1 = paginator.nextPage(bookmarkCount: 6)
        #expect(step1.previousPage == 0)
        #expect(step1.currentPage == 1)
        #expect(step1.totalPages == 3)
        #expect(step1.didChangePage)

        let step2 = paginator.nextPage(bookmarkCount: 6)
        #expect(step2.previousPage == 1)
        #expect(step2.currentPage == 2)
        #expect(step2.didChangePage)

        let back = paginator.previousPage(bookmarkCount: 6)
        #expect(back.previousPage == 2)
        #expect(back.currentPage == 1)
        #expect(back.didChangePage)
        #expect(paginator.currentPage(bookmarkCount: 6) == 1)
    }

    @Test func `Next wraps from last page to zero and previous wraps from zero to last page`() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let paginator = WidgetBookmarkPaginator(userDefaults: defaults)

        let wrapBack = paginator.previousPage(bookmarkCount: 5)
        #expect(wrapBack.previousPage == 0)
        #expect(wrapBack.currentPage == 2)
        #expect(wrapBack.totalPages == 3)
        #expect(wrapBack.didChangePage)

        let wrapForward = paginator.nextPage(bookmarkCount: 5)
        #expect(wrapForward.previousPage == 2)
        #expect(wrapForward.currentPage == 0)
        #expect(wrapForward.didChangePage)
    }

    // MARK: - Bookmark Count Changes & Edge Cases

    @Test func `Current page clamps and persists when bookmarks are deleted`() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let paginator = WidgetBookmarkPaginator(userDefaults: defaults)
        paginator.setCurrentPage(2, bookmarkCount: 6)
        #expect(paginator.currentPage(bookmarkCount: 6) == 2)

        // Delete 3 bookmarks -> 3 left (2 pages: 0 and 1).
        #expect(paginator.currentPage(bookmarkCount: 3) == 1)
        #expect(defaults.integer(forKey: WidgetBookmarkPaginator.currentPageDefaultsKey) == 1)

        // Delete down to 1 bookmark -> 1 page (index 0).
        #expect(paginator.currentPage(bookmarkCount: 1) == 0)

        // Delete all bookmarks -> clamps to 0.
        #expect(paginator.currentPage(bookmarkCount: 0) == 0)
    }

    @Test func `Single page and empty bookmark sets do not change page`() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let paginator = WidgetBookmarkPaginator(userDefaults: defaults)

        for count in [0, 1, 2] {
            let nextResult = paginator.nextPage(bookmarkCount: count)
            #expect(nextResult.currentPage == 0)
            #expect(!nextResult.didChangePage)

            let prevResult = paginator.previousPage(bookmarkCount: count)
            #expect(prevResult.currentPage == 0)
            #expect(!prevResult.didChangePage)
        }
    }

    @Test func `Separate paginator instances share page state across shared UserDefaults`() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = WidgetBookmarkPaginator(userDefaults: defaults)
        let second = WidgetBookmarkPaginator(userDefaults: defaults)

        let firstResult = first.nextPage(bookmarkCount: 6)
        #expect(firstResult.currentPage == 1)
        #expect(firstResult.didChangePage)

        let secondResult = second.nextPage(bookmarkCount: 6)
        #expect(secondResult.currentPage == 2)
        #expect(secondResult.didChangePage)
        #expect(first.currentPage(bookmarkCount: 6) == 2)
    }

    // MARK: - Localization Helpers

    @Test func `Pagination widget strings are populated`() {
        #expect(!WidgetStrings.previousPage.isEmpty)
        #expect(!WidgetStrings.nextPage.isEmpty)
        let indicator = WidgetStrings.pageIndicator(current: 2, total: 5)
        #expect(indicator.contains("2"))
        #expect(indicator.contains("5"))
    }
}
