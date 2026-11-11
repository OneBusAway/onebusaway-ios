//
//  MoreViewControllerTests.swift
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
@testable import OBAKitCore

/// Answers `OBAKitConfig` with the More tab and donations settings a test
/// chooses. A fresh temporary path per instance, since `Bundle` caches instances
/// by path and would otherwise hand back an earlier test's bundle.
// `nonisolated` and `@unchecked Sendable` for the same reasons as
// `DonationsConfigBundle` in DonationsManagerTests.
private nonisolated class MoreConfigBundle: Bundle, @unchecked Sendable {
    var moreTab: [String: Any] = [:]
    var donationsEnabledValue = false

    override func object(forInfoDictionaryKey key: String) -> Any? {
        if key == "OBAKitConfig" {
            return ["MoreTab": moreTab, "Donations": ["Enabled": donationsEnabledValue]]
        }
        return super.object(forInfoDictionaryKey: key)
    }

    static func create(moreTab: [String: Any], donationsEnabled: Bool) throws -> MoreConfigBundle {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bundle = try #require(MoreConfigBundle(path: dir.path))
        bundle.moreTab = moreTab
        bundle.donationsEnabledValue = donationsEnabled
        return bundle
    }
}

/// `Application.applicationBundle` is always `Bundle.main`; this one reads the
/// test's. It is set before `super.init`, because the donations manager is
/// built during init and reads the bundle then.
@MainActor
private final class MoreConfigApplication: Application {
    private let configBundle: Bundle
    override var applicationBundle: Bundle { configBundle }

    init(config: AppConfig, configBundle: Bundle) {
        self.configBundle = configBundle
        super.init(config: config)
    }
}

/// Records the URLs the More screen hands to the system.
@MainActor
private final class OpenedURLsDelegate: NSObject, ApplicationDelegate {
    var uiApplication: UIApplication?
    var isIdleTimerDisabled: Bool = false
    var isRegisteredForRemoteNotifications: Bool = false
    private(set) var openedURLs: [URL] = []

    func applicationReloadRootInterface(_ app: Application) {}
    func canOpenURL(_ url: URL) -> Bool { true }
    func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any], completionHandler completion: ((Bool) -> Void)?) {
        openedURLs.append(url)
    }
}

@Suite(.serialized)
final class MoreViewControllerTests: OBATestCase {

    private var queue: OperationQueue!
    private let openedURLs = OpenedURLsDelegate()

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Helpers

    /// `ShowHelpOutSection` is off unless a test turns it on, and `DevelopURL`
    /// is empty, so neither falls back to the shipped defaults.
    private func buildController(moreTab: [String: Any] = [:], donationsEnabled: Bool = false) throws -> MoreViewController {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: LocationService(userDefaults: userDefaults, locationManager: LocationManagerMock()),
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader,
            fixedRegionName: Fixtures.pugetSoundRegion.name,
            onDemandSupport: OnDemandSupport()
        )
        let settings: [String: Any] = ["ShowHelpOutSection": false, "DevelopURL": ""]
        let bundle = try MoreConfigBundle.create(moreTab: settings.merging(moreTab) { $1 }, donationsEnabled: donationsEnabled)
        let application = MoreConfigApplication(config: config, configBundle: bundle)
        application.delegate = openedURLs
        return MoreViewController(application: application)
    }

    private func sections(_ controller: MoreViewController) -> [OBAListViewSection] {
        controller.items(for: controller.listView)
    }

    private func rows(in sectionID: String, of controller: MoreViewController) throws -> [OBAListRowView.DefaultViewModel] {
        let section = try #require(sections(controller).first { $0.id == sectionID }, "No \(sectionID) section")
        return section.contents.compactMap { $0.as(OBAListRowView.DefaultViewModel.self) }
    }

    /// Taps every row in the section, in order, and returns the URLs they opened.
    private func urlsOpened(byTapping sectionID: String, of controller: MoreViewController) throws -> [URL] {
        for row in try rows(in: sectionID, of: controller) {
            row.onSelectAction?(row)
        }
        return openedURLs.openedURLs
    }

    /// Stores the US storefront answer the donations manager caches. The key
    /// copies `DonationsManager`'s private constant on purpose: if it is renamed,
    /// the donate tests fail rather than pass without a storefront answer.
    private func allowDonationsInStorefront() {
        userDefaults.set(true, forKey: "donationsStorefrontAllowsDonationsKey")
    }

    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    // MARK: - Sections

    @Test func `Without agency settings only the standard sections show`() throws {
        let controller = try buildController()

        #expect(sections(controller).map(\.id) == ["header", "updates_and_alerts", "my_location", "about"])
    }

    @Test func `Sections keep their order when every one is configured`() throws {
        allowDonationsInStorefront()
        let controller = try buildController(moreTab: [
            "ShowHelpOutSection": true,
            "TranslateURL": "https://example.com/translate",
            "TutorialURL": "https://example.com/tutorials",
            "CustomLinks": [["Title": "Rider Guide", "URL": "https://example.com/guide"]]
        ], donationsEnabled: true)

        #expect(sections(controller).map(\.id) == ["header", "donate", "updates_and_alerts", "my_location", "agency_contact", "help_out", "custom_links", "about"])
    }

    // MARK: - Contact & Help

    /// Each configured link gets a row; the missing phone number gets none.
    @Test func `Contact and help has a row for each configured link and opens it`() throws {
        let controller = try buildController(moreTab: [
            "TutorialURL": "https://example.com/tutorials",
            "TextURL": "sms:12345"
        ])

        #expect(try urlsOpened(byTapping: "agency_contact", of: controller) == [
            try url("https://example.com/tutorials"),
            try url("sms:12345")
        ])
    }

    @Test func `Contact and help opens the agency phone number`() throws {
        let controller = try buildController(moreTab: ["PhoneURL": "tel:+12065551234"])

        #expect(try urlsOpened(byTapping: "agency_contact", of: controller) == [try url("tel:+12065551234")])
    }

    // MARK: - Help Out

    @Test func `Help out stays hidden when switched off even with links set`() throws {
        let controller = try buildController(moreTab: [
            "ShowHelpOutSection": false,
            "TranslateURL": "https://example.com/translate",
            "DevelopURL": "https://example.com/develop"
        ])

        #expect(!sections(controller).contains { $0.id == "help_out" })
    }

    @Test func `Help out stays hidden when switched on with no links`() throws {
        let controller = try buildController(moreTab: ["ShowHelpOutSection": true])

        #expect(!sections(controller).contains { $0.id == "help_out" })
    }

    @Test func `Help out rows open the translate and develop links`() throws {
        let controller = try buildController(moreTab: [
            "ShowHelpOutSection": true,
            "TranslateURL": "https://example.com/translate",
            "DevelopURL": "https://example.com/develop"
        ])

        #expect(try urlsOpened(byTapping: "help_out", of: controller) == [
            try url("https://example.com/translate"),
            try url("https://example.com/develop")
        ])
    }

    // MARK: - Resources

    @Test func `Resources lists the custom links in order and opens each`() throws {
        let controller = try buildController(moreTab: ["CustomLinks": [
            ["Title": "Rider Guide", "URL": "https://example.com/guide"],
            ["Title": "Fares", "URL": "https://example.com/fares"]
        ]])

        let titles = try rows(in: "custom_links", of: controller).map { row -> String? in
            guard case .string(let title) = row.title else { return nil }
            return title
        }
        #expect(titles == ["Rider Guide", "Fares"])
        #expect(try urlsOpened(byTapping: "custom_links", of: controller) == [
            try url("https://example.com/guide"),
            try url("https://example.com/fares")
        ])
    }

    // MARK: - Donate

    /// The donate section also needs the US storefront answer the donations
    /// manager caches, and a sidecar to send donations to.
    @Test(arguments: [true, false])
    func `Donate section shows only when donations are enabled`(donationsEnabled: Bool) throws {
        allowDonationsInStorefront()
        let controller = try buildController(donationsEnabled: donationsEnabled)

        #expect(sections(controller).contains { $0.id == "donate" } == donationsEnabled)
    }
}
