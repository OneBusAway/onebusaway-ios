//
//  AgenciesViewControllerTests.swift
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

// swiftlint:disable force_cast

@MainActor
private final class DialRecordingApplicationDelegate: NSObject, ApplicationDelegate {
    var uiApplication: UIApplication?
    var isIdleTimerDisabled: Bool = false
    var isRegisteredForRemoteNotifications: Bool = false
    var openedURLs: [URL] = []

    func applicationReloadRootInterface(_ app: Application) {}

    func canOpenURL(_ url: URL) -> Bool { true }

    func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any], completionHandler completion: ((Bool) -> Void)?) {
        openedURLs.append(url)
        completion?(true)
    }
}

/// The Agencies screen's list and the options sheet each agency opens.
/// `OnDemandServicesListTests` covers when the on-demand option is offered.
@MainActor
@Suite(.serialized)
final class AgenciesViewControllerTests: OBATestCase {

    private var queue: OperationQueue!
    private var window: UIWindow?

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        window?.rootViewController?.dismiss(animated: false)
        window?.isHidden = true
        queue.cancelAllOperations()
    }

    // MARK: - Helpers

    private func buildController() -> (AgenciesViewController, Application) {
        let loader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: loader)
        let application = buildApplication(queue: queue, dataLoader: loader)
        return (AgenciesViewController(application: application), application)
    }

    /// The agencies in `agencies_with_coverage.json`, optionally rewriting one agency's
    /// phone number in the payload's references.
    private func agencies(phone: String? = nil, forAgencyID agencyID: String = "3") throws -> [AgencyWithCoverage] {
        var json = try JSONSerialization.jsonObject(with: Fixtures.loadData(file: "agencies_with_coverage.json")) as! [String: Any]
        if let phone {
            var data = json["data"] as! [String: Any]
            var references = data["references"] as! [String: Any]
            references["agencies"] = (references["agencies"] as! [[String: Any]]).map { agency in
                guard agency["id"] as? String == agencyID else { return agency }
                var agency = agency
                agency["phone"] = phone
                return agency
            }
            data["references"] = references
            json["data"] = data
        }
        let payload = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[AgencyWithCoverage]>.self, from: payload).list
    }

    private func agency(id: String, phone: String? = nil) throws -> AgencyWithCoverage {
        try #require(try agencies(phone: phone, forAgencyID: id).first { $0.agencyID == id })
    }

    /// Puts `controller` on screen so it can present.
    private func show(_ controller: UIViewController) throws {
        let window = UIWindow(windowScene: try testWindowScene())
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = controller
        window.isHidden = false
        self.window = window
    }

    private func trigger(_ action: UIAlertAction) {
        typealias Handler = @convention(block) (UIAlertAction) -> Void
        guard let block = action.value(forKey: "handler") else { return }
        unsafeBitCast(block as AnyObject, to: Handler.self)(action)
    }

    private func action(_ alert: UIAlertController, titled title: String) throws -> UIAlertAction {
        try #require(alert.actions.first { $0.title == title }, "No \(title) action in \(alert.actions.map(\.title))")
    }

    // MARK: - Options sheet

    @Test func `An agency with a phone number offers its website, a call, on-demand services and cancel`() throws {
        let (controller, _) = buildController()
        let pierce = try agency(id: "3")
        #expect(pierce.agency.phone == "(253)581-8000")

        let alert = controller.agencyOptionsAlert(pierce)

        #expect(alert.title == "Pierce Transit")
        #expect(alert.actions.dropLast().map(\.title) == ["Open Website", "Call Agency", Strings.agenciesOnDemandServices])
        #expect(alert.actions.last?.style == .cancel)
    }

    @Test func `An agency with no phone number offers no call`() throws {
        let (controller, _) = buildController()
        let childrens = try agency(id: "98")
        #expect(childrens.agency.phone.isEmpty)

        let alert = controller.agencyOptionsAlert(childrens)

        #expect(alert.actions.dropLast().map(\.title) == ["Open Website", Strings.agenciesOnDemandServices])
        #expect(alert.actions.last?.style == .cancel)
    }

    @Test func `Calling an agency dials its number`() throws {
        let (controller, application) = buildController()
        let delegate = DialRecordingApplicationDelegate()
        application.delegate = delegate

        let options = controller.agencyOptionsAlert(try agency(id: "3"))
        let call = try action(options, titled: "Call Agency")
        // The handler holds the controller weakly, and the alert must outlive its actions.
        withExtendedLifetime((controller, options)) { trigger(call) }

        #expect(delegate.openedURLs == [URL(string: "tel://2535818000")!])
    }

    @Test func `An agency phone number with no digits shows an error instead of dialing`() throws {
        let (controller, application) = buildController()
        let delegate = DialRecordingApplicationDelegate()
        application.delegate = delegate
        try show(controller)

        let options = controller.agencyOptionsAlert(try agency(id: "3", phone: "Ask the driver"))
        let call = try action(options, titled: "Call Agency")
        withExtendedLifetime((controller, options)) { trigger(call) }

        #expect(delegate.openedURLs.isEmpty)
        let error = try #require(controller.presentedViewController as? UIAlertController)
        #expect(error.message == "Invalid phone number.")
    }

    @Test func `On-demand services opens the services list`() throws {
        let (controller, _) = buildController()
        let navigation = UINavigationController(rootViewController: controller)

        let options = controller.agencyOptionsAlert(try agency(id: "3"))
        let onDemand = try action(options, titled: Strings.agenciesOnDemandServices)
        withExtendedLifetime((controller, options)) { trigger(onDemand) }

        #expect(navigation.viewControllers.count == 2)
        #expect(navigation.topViewController is OnDemandServicesListViewController)
    }

    // MARK: - List

    @Test func `Loaded agencies are listed by name, one row each`() async throws {
        let (controller, _) = buildController()
        #expect(controller.items(for: controller.listView).isEmpty)

        _ = try await controller.loadData()

        let rows = try #require(controller.items(for: controller.listView).first).contents
        let titles = rows.map { row -> String? in
            guard case .string(let title) = row.as(OBAListRowView.DefaultViewModel.self)?.title else { return nil }
            return title
        }
        #expect(titles == [
            "City of Seattle", "Community Transit", "Everett Transit", "Intercity Transit",
            "Kingcounty Marine Divison", "Metro Transit", "Pierce Transit", "Seattle Children's Hospital",
            "SeattleCenterMonorail", "Sound Transit", "Washington State Ferries"
        ])
    }

    @Test func `Tapping an agency opens its options`() async throws {
        let (controller, _) = buildController()
        _ = try await controller.loadData()
        try show(controller)
        let rows = try #require(controller.items(for: controller.listView).first).contents
        let pierce = try #require(rows.first { row in
            if case .string("Pierce Transit") = row.as(OBAListRowView.DefaultViewModel.self)?.title { return true }
            return false
        })

        pierce.onSelectAction?(pierce)

        let options = try #require(controller.presentedViewController as? UIAlertController)
        #expect(options.title == "Pierce Transit")
    }
}

// swiftlint:enable force_cast
