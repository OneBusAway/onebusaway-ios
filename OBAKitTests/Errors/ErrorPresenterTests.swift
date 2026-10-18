//
//  ErrorPresenterTests.swift
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

@MainActor
@Suite(.serialized)
final class ErrorPresenterTests {

    private func report(status: Int, path: String = "stop/1_75403.json") -> ErrorReport {
        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/\(path)")!
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return ErrorReport(error: APIError.requestFailure(response), regionName: "Puget Sound", systemVersion: "26.1", deviceModel: "iPhone16,1")
    }

    @Test func `Presents when nothing is up`() {
        #expect(ErrorPresenter.shouldPresent(report(status: 500), current: nil, isShowingDetails: false))
    }

    /// #1421: one dead stop among the bookmarks produces a burst of identical
    /// errors. They collapse into the toast already up, even though each one
    /// carries its own reference code.
    @Test func `Drops a repeat of the toast already up`() {
        #expect(!ErrorPresenter.shouldPresent(report(status: 500), current: report(status: 500), isShowingDetails: false))
    }

    @Test func `Replaces a toast that says something else`() {
        #expect(ErrorPresenter.shouldPresent(report(status: 429), current: report(status: 500), isShowingDetails: false))
    }

    @Test func `Never covers an open details page`() {
        #expect(!ErrorPresenter.shouldPresent(report(status: 429), current: nil, isShowingDetails: true))
    }

    @Test func `Never presents a silent report`() {
        let silent = ErrorReport(error: APIError.surveyServiceNotConfigured, regionName: nil, systemVersion: "26.1", deviceModel: "x")
        #expect(!ErrorPresenter.shouldPresent(silent, current: nil, isShowingDetails: false))
    }

    @Test func `Toast style follows whose fix it is`() {
        #expect(ErrorToast(report: report(status: 500)).style == .problem)
        #expect(ErrorToast(report: report(status: 500)).actionTitle == ErrorStrings.details)

        let cellular = ErrorReport(
            error: APIError.networkFailure(nil), regionName: "Puget Sound", isCellularDataRestricted: true,
            systemVersion: "26.1", deviceModel: "x"
        )
        #expect(ErrorToast(report: cellular).style == .riderAction)
        #expect(ErrorToast(report: cellular).actionTitle == Strings.settings)
    }
}
