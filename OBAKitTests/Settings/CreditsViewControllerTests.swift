//
//  CreditsViewControllerTests.swift
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

@MainActor
private final class CreditsApplicationDelegate: NSObject, ApplicationDelegate {
    var uiApplication: UIApplication?
    var isIdleTimerDisabled: Bool = false
    var isRegisteredForRemoteNotifications: Bool = false
    let credits: [String: String]

    init(credits: [String: String]) {
        self.credits = credits
    }

    func applicationReloadRootInterface(_ app: Application) {}
    func canOpenURL(_ url: URL) -> Bool { false }
    func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any], completionHandler completion: ((Bool) -> Void)?) {}
}

/// Settings > Credits: the framework's `OBAKit_Credits.plist`, plus whatever the app adds.
@Suite(.serialized)
final class CreditsViewControllerTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Helpers

    private func buildController(appCredits: [String: String] = [:]) -> (CreditsViewController, CreditsApplicationDelegate) {
        let loader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: loader)
        let application = buildApplication(queue: queue, dataLoader: loader)
        let delegate = CreditsApplicationDelegate(credits: appCredits)
        application.delegate = delegate
        return (CreditsViewController(application: application), delegate)
    }

    private func plistCredits() throws -> [String: String] {
        let path = try #require(Bundle.obaKit.path(forResource: "OBAKit_Credits", ofType: "plist"))
        let plist = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
        return plist
    }

    private func rows(_ controller: CreditsViewController) -> [OBAListRowView.DefaultViewModel] {
        controller.items(for: controller.listView).flatMap(\.contents).compactMap { $0.as(OBAListRowView.DefaultViewModel.self) }
    }

    private func titles(_ controller: CreditsViewController) -> [String] {
        rows(controller).compactMap { row in
            guard case .string(let title) = row.title else { return nil }
            return title
        }
    }

    /// Taps the row titled `title` and returns the license viewer it pushed.
    private func open(_ title: String, in controller: CreditsViewController) throws -> CreditViewerController {
        let navigation = UINavigationController(rootViewController: controller)
        let row = try #require(rows(controller).first { row in
            if case .string(title) = row.title { return true }
            return false
        })
        withExtendedLifetime(controller) {
            row.onSelectAction?(row)
        }
        #expect(navigation.viewControllers.count == 2)
        return try #require(navigation.topViewController as? CreditViewerController)
    }

    private func licenseText(_ viewer: CreditViewerController) -> String? {
        Mirror(reflecting: viewer).descendant("licenseText") as? String
    }

    // MARK: - Tests

    /// A library copied into OBAKit/ThirdParty ships inside the app, so its license must be on this screen.
    @Test func `Every library vendored under OBAKit/ThirdParty is credited on the screen`() throws {
        let thirdParty = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("OBAKit/ThirdParty")
        let vendored = try FileManager.default
            .contentsOfDirectory(at: thirdParty, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }
            .map(\.lastPathComponent)
        #expect(!vendored.isEmpty, "Found no vendored libraries at \(thirdParty.path)")

        let credits = try plistCredits()
        let (controller, delegate) = buildController()
        let listed = withExtendedLifetime(delegate) { titles(controller) }

        for library in vendored {
            #expect(credits[library]?.isEmpty == false, "\(library) has no license in OBAKit_Credits.plist")
            #expect(listed.contains(library), "\(library) is not listed on the Credits screen")
        }
    }

    @Test func `The screen lists the framework's credits and the app's, ignoring case when sorting`() throws {
        let appCredits = ["abseil": "Apache License", "zlib": "zlib License"]
        let (controller, delegate) = buildController(appCredits: appCredits)
        let listed = withExtendedLifetime(delegate) { titles(controller) }

        let expected = Set(try plistCredits().keys).union(appCredits.keys)
        #expect(Set(listed) == expected)
        #expect(listed.count == expected.count)

        // Sorted by case, "abseil" and "zlib" would both follow every capitalized name.
        #expect(listed.first == "abseil")
        #expect(listed.last == "zlib")
        for (earlier, later) in zip(listed, listed.dropFirst()) {
            #expect(earlier.localizedCaseInsensitiveCompare(later) == .orderedAscending, "\(earlier) is listed before \(later)")
        }
    }

    @Test func `Tapping a library opens its license under its name`() throws {
        let (controller, delegate) = buildController()

        let viewer = try withExtendedLifetime(delegate) { try open("BulletinBoard", in: controller) }

        #expect(viewer.title == "BulletinBoard")
        #expect(licenseText(viewer) == (try plistCredits()["BulletinBoard"]))
    }

    @Test func `An app credit with the same name replaces the framework's`() throws {
        let (controller, delegate) = buildController(appCredits: ["FloatingPanel": "The app's FloatingPanel license"])

        let viewer = try withExtendedLifetime(delegate) { () throws -> CreditViewerController in
            #expect(titles(controller).filter { $0 == "FloatingPanel" }.count == 1)
            return try open("FloatingPanel", in: controller)
        }

        #expect(licenseText(viewer) == "The app's FloatingPanel license")
    }
}
