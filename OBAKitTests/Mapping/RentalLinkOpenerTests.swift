//
//  RentalLinkOpenerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit

/// The fallback ladder behind both map surfaces' "Open in <operator>" button.
/// Every collaborator is a closure, so these run without UIKit opening anything.
@MainActor
@Suite(.serialized)
final class RentalLinkOpenerTests {

    private struct Opened: Equatable {
        let url: String
        let universalLinksOnly: Bool
    }

    private var opened: [Opened] = []
    private var reported: [String] = []
    private var storeRequests: [String] = []

    /// What each successive `open` reports, in order. Runs out to `true`.
    private var openResults: [Bool] = []
    private var storeLoads = true

    private func makeOpener() -> RentalLinkOpener {
        RentalLinkOpener(
            open: { [unowned self] url, options, completion in
                opened.append(Opened(url: url.absoluteString, universalLinksOnly: options[.universalLinksOnly] as? Bool == true))
                completion(openResults.isEmpty ? true : openResults.removeFirst())
            },
            report: { [unowned self] label, _ in reported.append(label) },
            presentStore: { [unowned self] id, completion in
                storeRequests.append(id)
                completion(storeLoads)
            }
        )
    }

    private func target(_ url: String, storeFallback: String? = nil, appStoreID: String? = nil) -> RentalDeepLink.Target {
        RentalDeepLink.Target(
            url: URL(string: url)!,
            storeFallback: storeFallback.flatMap(URL.init(string:)),
            operatorName: "Lime",
            appStoreID: appStoreID
        )
    }

    @Test func successfulOpenLogsOnlyTheTap() {
        openResults = [true]
        makeOpener().open(target("limebike://map?selected_vehicle_id=a", appStoreID: "1199780189"), networkID: "lime_seattle")

        #expect(opened == [Opened(url: "limebike://map?selected_vehicle_id=a", universalLinksOnly: false)])
        #expect(reported == [AnalyticsLabels.rentalDeepLinkTapped])
        #expect(storeRequests.isEmpty)
    }

    /// The common case on the launch feed: Lime is not installed.
    @Test func failedOpenPresentsTheStorePageInApp() {
        openResults = [false]
        makeOpener().open(target("limebike://map", storeFallback: "https://apps.apple.com/app/id1199780189", appStoreID: "1199780189"), networkID: "lime_seattle")

        #expect(reported == [AnalyticsLabels.rentalDeepLinkTapped, AnalyticsLabels.rentalDeepLinkFallbackFired])
        #expect(storeRequests == ["1199780189"])
        #expect(opened.count == 1)
    }

    @Test func storePageThatCannotLoadOpensTheWebAppStore() {
        openResults = [false]
        storeLoads = false
        makeOpener().open(target("limebike://map", appStoreID: "1199780189"), networkID: nil)

        #expect(opened.last == Opened(url: "https://apps.apple.com/app/id1199780189", universalLinksOnly: false))
    }

    /// https feed links try the operator's app first, and only it.
    @Test func webLinksOpenAsUniversalLinksFirst() {
        openResults = [true]
        makeOpener().open(target("https://lime.example/ride/abc"), networkID: nil)

        #expect(opened == [Opened(url: "https://lime.example/ride/abc", universalLinksOnly: true)])
    }

    @Test func webLinkWithoutAnAppOpensInSafariWhenNoStoreIDIsKnown() {
        openResults = [false]
        makeOpener().open(target("https://ride.example/abc", storeFallback: "https://ride.example/"), networkID: nil)

        #expect(opened == [
            Opened(url: "https://ride.example/abc", universalLinksOnly: true),
            Opened(url: "https://ride.example/abc", universalLinksOnly: false)
        ])
        #expect(storeRequests.isEmpty)
        #expect(reported.last == AnalyticsLabels.rentalDeepLinkFallbackFired)
    }

    @Test func webLinkWithoutAnAppPrefersTheStoreWhenTheIDIsKnown() {
        openResults = [false]
        makeOpener().open(target("https://lime.example/ride/abc", appStoreID: "1199780189"), networkID: nil)

        #expect(storeRequests == ["1199780189"])
        #expect(opened.count == 1)
    }

    @Test func customSchemeWithoutAStoreIDUsesTheStoreFallback() {
        openResults = [false]
        makeOpener().open(target("veo://ride", storeFallback: "https://www.veoride.com/"), networkID: nil)

        #expect(opened.last == Opened(url: "https://www.veoride.com/", universalLinksOnly: false))
        #expect(reported == [AnalyticsLabels.rentalDeepLinkTapped, AnalyticsLabels.rentalDeepLinkFallbackFired])
    }

    /// Callers build an opener per tap and drop it; the fallback must still run
    /// when the open completes after that.
    @Test func fallbackRunsAfterTheCallerDropsTheOpener() {
        var pending: ((Bool) -> Void)?
        var storeIDs: [String] = []
        RentalLinkOpener(
            open: { _, _, completion in pending = completion },
            report: { _, _ in },
            presentStore: { id, _ in storeIDs.append(id) }
        ).open(target("limebike://map", appStoreID: "1199780189"), networkID: nil)

        pending?(false)
        #expect(storeIDs == ["1199780189"])
    }
}
