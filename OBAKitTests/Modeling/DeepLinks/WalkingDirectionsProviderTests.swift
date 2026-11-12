//
//  WalkingDirectionsProviderTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@MainActor
private final class WalkingDirectionsDelegate: NSObject, ApplicationDelegate {
    var uiApplication: UIApplication?
    var isIdleTimerDisabled = false
    var isRegisteredForRemoteNotifications = false
    var openedURLs: [URL] = []

    func applicationReloadRootInterface(_ app: Application) {}
    func canOpenURL(_ url: URL) -> Bool { false }
    func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any], completionHandler completion: ((Bool) -> Void)?) {
        openedURLs.append(url)
        completion?(true)
    }
}

@MainActor
@Suite(.serialized)
final class WalkingDirectionsProviderTests: OBATestCase {
    private let coordinate = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)

    @Test func `Ask every time offers both installed providers`() {
        let options = WalkingDirectionsProvider.options(coordinate: coordinate, preferred: .askEveryTime, googleMapsAvailable: true)

        #expect(options.map(\.provider) == [.appleMaps, .googleMaps])
    }

    @Test(arguments: [WalkingDirectionsProvider.appleMaps, .googleMaps])
    func `A preferred provider bypasses the chooser and keeps the walking destination`(provider: WalkingDirectionsProvider) throws {
        let options = WalkingDirectionsProvider.options(coordinate: coordinate, preferred: provider, googleMapsAvailable: true)

        #expect(options.count == 1)
        let option = try #require(options.first)
        #expect(option.provider == provider)
        let components = try #require(URLComponents(url: option.url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.contains(URLQueryItem(name: "daddr", value: "47.6,-122.3")) == true)
        if provider == .googleMaps {
            #expect(components.scheme == "comgooglemaps")
            #expect(components.queryItems?.contains(URLQueryItem(name: "directionsmode", value: "walking")) == true)
        } else {
            #expect(components.host == "maps.apple.com")
            #expect(components.queryItems?.contains(URLQueryItem(name: "dirflg", value: "w")) == true)
        }
    }

    @Test func `An unavailable Google Maps preference falls back to Apple Maps`() {
        let options = WalkingDirectionsProvider.options(coordinate: coordinate, preferred: .googleMaps, googleMapsAvailable: false)

        #expect(options.map(\.provider) == [.appleMaps])
    }

    @Test func `The More menu keeps the chooser until a provider is selected`() throws {
        let queue = OperationQueue()
        defer { queue.cancelAllOperations() }
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let chooser = WalkingDirectionsProvider.menuElement(coordinate: coordinate, application: application, googleMapsAvailable: true)
        let menu = try #require(chooser as? UIMenu)
        #expect(menu.children.count == 2)

        application.userDefaults.set(WalkingDirectionsProvider.googleMaps.rawValue, forKey: WalkingDirectionsProvider.defaultsKey)
        let preferred = WalkingDirectionsProvider.menuElement(coordinate: coordinate, application: application, googleMapsAvailable: true)
        #expect(preferred is UIAction)
        let fallback = WalkingDirectionsProvider.menuElement(coordinate: coordinate, application: application, googleMapsAvailable: false)
        #expect(fallback is UIAction)
        #expect(WalkingDirectionsProvider(userDefaults: application.userDefaults) == .googleMaps)
    }

    @Test func `The More menu disables directions before the stop loads`() throws {
        let queue = OperationQueue()
        defer { queue.cancelAllOperations() }
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let element = WalkingDirectionsProvider.menuElement(coordinate: nil, application: application, googleMapsAvailable: false)

        let action = try #require(element as? UIAction)
        #expect(action.attributes.contains(.disabled))
    }

    @Test func `Returning to an existing stop refreshes its walking directions preference`() throws {
        let queue = OperationQueue()
        defer { queue.cancelAllOperations() }
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let stop = try #require(Fixtures.loadSomeStops().first)
        let controller = StopPageViewController(application: application, stop: stop)
        controller.loadViewIfNeeded()

        func directionsElement() throws -> UIMenuElement {
            let menus = (controller.navigationItem.rightBarButtonItems ?? []).compactMap(\.menu)
            let sections = menus.flatMap { $0.children.compactMap { $0 as? UIMenu } }
            return try #require(sections.flatMap(\.children).first { $0.title == WalkingDirectionsProvider.askEveryTime.actionTitle })
        }
        #expect(try directionsElement() is UIMenu)
        let settings = SettingsViewModel(application: application)
        settings.walkingDirectionsProvider = .appleMaps

        controller.viewWillAppear(false)

        #expect(try directionsElement() is UIAction)
        controller.viewWillDisappear(false)
    }

    /// Google Maps is excluded on the simulator. Its selected preference must
    /// still open the available provider, without silently changing the setting.
    @Test(arguments: [WalkingDirectionsProvider.appleMaps, .googleMaps])
    func `The presenter opens walking directions without presenting a chooser`(provider: WalkingDirectionsProvider) throws {
        let queue = OperationQueue()
        defer { queue.cancelAllOperations() }
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let delegate = WalkingDirectionsDelegate()
        application.delegate = delegate
        application.userDefaults.set(provider.rawValue, forKey: WalkingDirectionsProvider.defaultsKey)
        let host = UIViewController()
        let presenter = StopPageActionPresenter(application: application, presentingController: { host })

        presenter.showWalkingDirections(coordinate: coordinate)

        let expectedURL = try #require(AppInterop.appleMapsWalkingDirectionsURL(coordinate: coordinate))
        #expect(delegate.openedURLs == [expectedURL])
        #expect(host.presentedViewController == nil)
        #expect(WalkingDirectionsProvider(userDefaults: application.userDefaults) == provider)
    }
}
