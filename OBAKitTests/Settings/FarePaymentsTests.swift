//
//  FarePaymentsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

@testable import OBAKit
@testable import OBAKitCore
import Foundation
import StoreKit
import Testing
import UIKit

// MARK: - Mocks

@MainActor
private final class MockFarePaymentsDelegate: NSObject, FarePaymentsDelegate {
    var presentedViewController: UIViewController?
    var presentedAnimated: Bool?
    var presentedError: Error?

    func farePayments(_ farePayments: FarePayments, present viewController: UIViewController, animated: Bool, completion: VoidBlock?) {
        presentedViewController = viewController
        presentedAnimated = animated
        completion?()
    }

    func farePayments(_ farePayments: FarePayments, present error: Error) {
        presentedError = error
    }
}

@MainActor
private final class MockApplicationDelegate: NSObject, ApplicationDelegate {
    var uiApplication: UIApplication?
    var canOpenURLResult: Bool = false
    var openedURLs: [URL] = []
    var isIdleTimerDisabled: Bool = false
    var isRegisteredForRemoteNotifications: Bool = false

    func applicationReloadRootInterface(_ app: Application) {}

    func canOpenURL(_ url: URL) -> Bool {
        return canOpenURLResult
    }

    func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any], completionHandler completion: ((Bool) -> Void)?) {
        openedURLs.append(url)
        completion?(true)
    }
}

// MARK: - Test Suite

@MainActor
@Suite(.serialized)
final class FarePaymentsTests: OBATestCase {

    private var queue: OperationQueue!
    private var application: Application!
    private var mockApplicationDelegate: MockApplicationDelegate!
    private var delegate: MockFarePaymentsDelegate!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        mockApplicationDelegate = MockApplicationDelegate()
        application.delegate = mockApplicationDelegate
        delegate = MockFarePaymentsDelegate()
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private var analyticsMock: AnalyticsMock {
        application.analytics as! AnalyticsMock
    }

    private func englishBundle() -> Bundle? {
        guard let path = Bundle(for: FarePayments.self).path(forResource: "en", ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    private func triggerAlertAction(_ action: UIAlertAction) {
        typealias Handler = @convention(block) (UIAlertAction) -> Void
        guard let block = action.value(forKey: "handler") else { return }
        unsafeBitCast(block as AnyObject, to: Handler.self)(action)
    }

    // MARK: - Region Availability

    @Test func `Workflow returns early without side effects when current region is nil`() {
        application.userDefaults.removeObject(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        #expect(application.currentRegion == nil)

        let farePayments = FarePayments(application: application, delegate: delegate)
        farePayments.beginFarePaymentsWorkflow()

        #expect(delegate.presentedViewController == nil)
        #expect(delegate.presentedError == nil)
        #expect(mockApplicationDelegate.openedURLs.isEmpty)
        #expect(analyticsMock.reportedEvents.isEmpty)
    }

    // MARK: - Warning Alert

    @Test func `Warning alert is presented when region payment app does not cover full region`() throws {
        #expect(Fixtures.pugetSoundRegion.paymentAppDoesNotCoverFullRegion)

        let farePayments = FarePayments(application: application, delegate: delegate)
        farePayments.beginFarePaymentsWorkflow()

        let alert = try #require(delegate.presentedViewController as? UIAlertController)
        #expect(alert.title == Fixtures.pugetSoundRegion.paymentWarningTitle)
        #expect(alert.message == Fixtures.pugetSoundRegion.paymentWarningBody)
        #expect(alert.preferredStyle == .alert)
        #expect(alert.actions.count == 3)

        // Cancel action
        let cancelAction = alert.actions[0]
        #expect(cancelAction.style == .cancel)
        #expect(cancelAction.title == Strings.cancel)
        let warningDefaultsKey = "ShowPaymentWarning_Region_\(Fixtures.pugetSoundRegion.regionIdentifier)"
        withExtendedLifetime(farePayments) {
            triggerAlertAction(cancelAction)
        }
        #expect(application.userDefaults.bool(forKey: warningDefaultsKey))
        #expect(mockApplicationDelegate.openedURLs.isEmpty)
        #expect(analyticsMock.reportedEvents.isEmpty)

        // Continue and Don't Show Again action
        let expectedDontShowAgainTitle = Bundle(for: FarePayments.self).localizedString(forKey: "fare_payments.dont_show_again", value: nil, table: nil)
        #expect(alert.actions[1].title == expectedDontShowAgainTitle)

        // Continue action
        #expect(alert.actions[2].title == Strings.continue)

        #expect(delegate.presentedAnimated == true)
    }

    @Test func `Continue and dont show again action disables future warning and launches app`() throws {
        mockApplicationDelegate.canOpenURLResult = true

        let farePayments = FarePayments(application: application, delegate: delegate)
        farePayments.beginFarePaymentsWorkflow()

        let alert = try #require(delegate.presentedViewController as? UIAlertController)
        let warningDefaultsKey = "ShowPaymentWarning_Region_\(Fixtures.pugetSoundRegion.regionIdentifier)"
        #expect(application.userDefaults.bool(forKey: warningDefaultsKey))

        withExtendedLifetime(farePayments) {
            triggerAlertAction(alert.actions[1])
        }

        #expect(!application.userDefaults.bool(forKey: warningDefaultsKey))
        #expect(mockApplicationDelegate.openedURLs == [Fixtures.pugetSoundRegion.paymentAppDeepLinkURL!])

        let hasOpenEvent = analyticsMock.reportedEvents.contains { event in
            event.pageURL == "app://localhost/fare-payments" &&
            event.label == AnalyticsLabels.farePayment &&
            (event.value as? String) == "open_app"
        }
        #expect(hasOpenEvent)
    }

    @Test func `Continue action preserves warning defaults flag and launches app`() throws {
        mockApplicationDelegate.canOpenURLResult = true

        let farePayments = FarePayments(application: application, delegate: delegate)
        farePayments.beginFarePaymentsWorkflow()

        let alert = try #require(delegate.presentedViewController as? UIAlertController)
        let warningDefaultsKey = "ShowPaymentWarning_Region_\(Fixtures.pugetSoundRegion.regionIdentifier)"

        withExtendedLifetime(farePayments) {
            triggerAlertAction(alert.actions[2])
        }

        #expect(application.userDefaults.bool(forKey: warningDefaultsKey))
        #expect(mockApplicationDelegate.openedURLs == [Fixtures.pugetSoundRegion.paymentAppDeepLinkURL!])

        let hasOpenEvent = analyticsMock.reportedEvents.contains { event in
            event.pageURL == "app://localhost/fare-payments" &&
            event.label == AnalyticsLabels.farePayment &&
            (event.value as? String) == "open_app"
        }
        #expect(hasOpenEvent)
    }

    @Test func `Warning alert is bypassed when user defaults flag is already false`() {
        mockApplicationDelegate.canOpenURLResult = true
        let warningDefaultsKey = "ShowPaymentWarning_Region_\(Fixtures.pugetSoundRegion.regionIdentifier)"
        application.userDefaults.set(false, forKey: warningDefaultsKey)

        let farePayments = FarePayments(application: application, delegate: delegate)
        farePayments.beginFarePaymentsWorkflow()

        #expect(delegate.presentedViewController == nil)
        #expect(mockApplicationDelegate.openedURLs == [Fixtures.pugetSoundRegion.paymentAppDeepLinkURL!])

        let hasOpenEvent = analyticsMock.reportedEvents.contains { event in
            event.pageURL == "app://localhost/fare-payments" &&
            event.label == AnalyticsLabels.farePayment &&
            (event.value as? String) == "open_app"
        }
        #expect(hasOpenEvent)
    }

    @Test func `Warning alert is bypassed when region payment app covers full region`() {
        mockApplicationDelegate.canOpenURLResult = true
        application.regionsService.currentRegion = Fixtures.tampaRegion
        #expect(!Fixtures.tampaRegion.paymentAppDoesNotCoverFullRegion)

        let farePayments = FarePayments(application: application, delegate: delegate)
        farePayments.beginFarePaymentsWorkflow()

        #expect(delegate.presentedViewController == nil)
        #expect(mockApplicationDelegate.openedURLs == [Fixtures.tampaRegion.paymentAppDeepLinkURL!])

        let hasOpenEvent = analyticsMock.reportedEvents.contains { event in
            event.pageURL == "app://localhost/fare-payments" &&
            event.label == AnalyticsLabels.farePayment &&
            (event.value as? String) == "open_app"
        }
        #expect(hasOpenEvent)
    }

    // MARK: - App Launch & App Store Fallback

    @Test func `When app is not installed download event is reported and App Store page is presented`() throws {
        mockApplicationDelegate.canOpenURLResult = false
        let warningDefaultsKey = "ShowPaymentWarning_Region_\(Fixtures.pugetSoundRegion.regionIdentifier)"
        application.userDefaults.set(false, forKey: warningDefaultsKey)

        let farePayments = FarePayments(application: application, delegate: delegate)
        farePayments.beginFarePaymentsWorkflow()

        #expect(mockApplicationDelegate.openedURLs.isEmpty)

        let hasDownloadEvent = analyticsMock.reportedEvents.contains { event in
            event.pageURL == "app://localhost/fare-payments" &&
            event.label == AnalyticsLabels.farePayment &&
            (event.value as? String) == "download_app"
        }
        #expect(hasDownloadEvent)

        let storeController = try #require(delegate.presentedViewController as? SKStoreProductViewController)
        #expect(storeController.delegate === farePayments)
        #expect(delegate.presentedAnimated == true)
    }

    @Test func `When region has no payment app deep link URL workflow returns early`() throws {
        let mtaRegion = try #require(application.regionsService.find(id: 2))
        application.regionsService.currentRegion = mtaRegion
        #expect(application.currentRegion != nil)
        #expect(mtaRegion.paymentAppDeepLinkURL == nil)

        let farePayments = FarePayments(application: application, delegate: delegate)
        farePayments.beginFarePaymentsWorkflow()

        #expect(delegate.presentedViewController == nil)
        #expect(mockApplicationDelegate.openedURLs.isEmpty)
        #expect(analyticsMock.reportedEvents.isEmpty)
    }

    // MARK: - String Catalog Integrity

    @Test func `Dont show again button localization key exists in English and framework bundle`() throws {
        let key = "fare_payments.dont_show_again"
        let fallback = "Continue and Don't Show Again"

        let bundle = try #require(englishBundle())
        let localizedEnglish = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
        #expect(localizedEnglish != "MISSING", "\(key) is missing from the English catalog")
        #expect(localizedEnglish == fallback)

        let frameworkBundle = Bundle(for: FarePayments.self)
        let localizedFramework = frameworkBundle.localizedString(forKey: key, value: "MISSING", table: nil)
        #expect(localizedFramework != "MISSING", "\(key) is missing from the framework catalog")
        #expect(!localizedFramework.isEmpty, "\(key) resolved to an empty string in the framework catalog")
        #expect(localizedFramework != key, "\(key) fell back to the key name in the framework catalog")
    }
}
