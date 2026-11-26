//
//  RootInterfaceSwapTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

@testable import OBAKit
@testable import OBAKitCore
import Combine
import Foundation
import MapKit
import UIKit
import Testing

/// The map experience toggle replaces the window's root while the old root is still presenting
/// sheets (in the panel: the floating sheet, the More sheet on it, and Settings). These tests use
/// a real window so UIKit's own presentation bookkeeping decides what is dismissed and what is
/// freed.
@MainActor
@Suite(.serialized)
final class RootInterfaceSwapTests: OBATestCase {

    private let window: UIWindow

    override init() async throws {
        window = UIWindow(windowScene: try testWindowScene())
        try await super.init()
    }

    isolated deinit {
        window.isHidden = true
        window.rootViewController = nil
    }

    // MARK: - Nothing presented

    /// First launch: the window has no root yet, so there is nothing to dismiss.
    @Test func `A window with no root gets the new one at once`() {
        let newRoot = UIViewController()
        var completions = 0

        RootInterfaceSwap.replaceRoot(of: window) { newRoot } completion: { completions += 1 }

        #expect(window.rootViewController === newRoot)
        #expect(completions == 1)
    }

    @Test func `With nothing presented the new root goes in at once`() {
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        let newRoot = UIViewController()
        var completions = 0

        RootInterfaceSwap.replaceRoot(of: window) { newRoot } completion: { completions += 1 }

        #expect(window.rootViewController === newRoot)
        #expect(completions == 1)
    }

    // MARK: - Presentation chain

    @Test(.timeLimit(.minutes(1)))
    func `Everything the old root presents is dismissed before the new root is built`() async throws {
        let oldRoot = UIViewController()
        install(oldRoot)
        let sheet = UIViewController()
        let stacked = UIViewController()
        await present(sheet, from: oldRoot)
        await present(stacked, from: sheet)
        try #require(oldRoot.presentedViewController === sheet)

        var chainWhenBuilt: UIViewController?
        let newRoot = UIViewController()
        await swap { chainWhenBuilt = oldRoot.presentedViewController; return newRoot }

        #expect(chainWhenBuilt == nil)
        #expect(window.rootViewController === newRoot)
        #expect(sheet.presentingViewController == nil)
        #expect(stacked.presentingViewController == nil)
        #expect(stacked.viewIfLoaded?.window == nil)
        #expect(newRoot.presentedViewController == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func `The completion runs after the new root is in place`() async {
        let oldRoot = UIViewController()
        install(oldRoot)
        await present(UIViewController(), from: oldRoot)
        let newRoot = UIViewController()

        let rootAtCompletion: UIViewController? = await withCheckedContinuation { continuation in
            RootInterfaceSwap.replaceRoot(of: window) { newRoot } completion: { [window] in
                continuation.resume(returning: window.rootViewController)
            }
        }

        #expect(rootAtCompletion === newRoot)
    }

    // MARK: - Back-to-back reloads

    @Test func `Back-to-back reloads coalesce to the latest root and fire every completion`() {
        let testWindow = UIWindow(frame: .zero)
        let oldRoot = DeferredDismissViewController()
        testWindow.rootViewController = oldRoot

        var built: [String] = []
        var completed: [String] = []
        let firstRoot = UIViewController()
        let secondRoot = UIViewController()
        let thirdRoot = UIViewController()

        RootInterfaceSwap.replaceRoot(of: testWindow, with: {
            built.append("first")
            return firstRoot
        }, completion: {
            completed.append("first")
        })
        RootInterfaceSwap.replaceRoot(of: testWindow, with: {
            built.append("second")
            return secondRoot
        }, completion: {
            completed.append("second")
        })
        RootInterfaceSwap.replaceRoot(of: testWindow, with: {
            built.append("third")
            return thirdRoot
        }, completion: {
            completed.append("third")
        })

        #expect(oldRoot.dismissCallCount == 1)
        #expect(built.isEmpty)
        #expect(completed.isEmpty)
        #expect(testWindow.rootViewController === oldRoot)

        oldRoot.finishDismissal()

        #expect(testWindow.rootViewController === thirdRoot)
        #expect(built == ["third"])
        #expect(completed == ["first", "second", "third"])

        // State for this window is cleared once the dismissal finishes, so a later swap works normally.
        let fourthRoot = UIViewController()
        var fourthCompleted = false
        RootInterfaceSwap.replaceRoot(of: testWindow, with: { fourthRoot }, completion: { fourthCompleted = true })
        #expect(testWindow.rootViewController === fourthRoot)
        #expect(fourthCompleted)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Back-to-back reloads on a real presentation chain install the latest root`() async throws {
        let oldRoot = UIViewController()
        install(oldRoot)
        await present(UIViewController(), from: oldRoot)
        try #require(oldRoot.presentedViewController != nil)

        var built: [String] = []
        var completed: [String] = []
        let firstRoot = UIViewController()
        let secondRoot = UIViewController()

        await withCheckedContinuation { continuation in
            RootInterfaceSwap.replaceRoot(of: window, with: {
                built.append("first")
                return firstRoot
            }, completion: {
                completed.append("first")
            })
            RootInterfaceSwap.replaceRoot(of: window, with: {
                built.append("second")
                return secondRoot
            }, completion: {
                completed.append("second")
                continuation.resume()
            })
        }

        #expect(oldRoot.presentedViewController == nil)
        #expect(window.rootViewController === secondRoot)
        // UIKit normally invokes `dismiss`'s completion asynchronously (so only
        // "second" builds), but synchronous completion is also a valid schedule.
        #expect(built == ["second"] || built == ["first", "second"])
        #expect(completed == ["first", "second"])
    }

    @Test func `A reload triggered from a completion runs cleanly`() {
        let testWindow = UIWindow(frame: .zero)
        let oldRoot = DeferredDismissViewController()
        testWindow.rootViewController = oldRoot

        let firstRoot = UIViewController()
        let followUpRoot = UIViewController()
        var events: [String] = []

        RootInterfaceSwap.replaceRoot(of: testWindow, with: {
            events.append("build-first")
            return firstRoot
        }, completion: {
            events.append("complete-first")
            RootInterfaceSwap.replaceRoot(of: testWindow, with: {
                events.append("build-followup")
                return followUpRoot
            }, completion: {
                events.append("complete-followup")
            })
        })

        oldRoot.finishDismissal()

        #expect(testWindow.rootViewController === followUpRoot)
        #expect(events == ["build-first", "complete-first", "build-followup", "complete-followup"])
    }

    @Test func `An in-flight dismissal on one window does not block another window`() {
        let firstWindow = UIWindow(frame: .zero)
        let oldRoot = DeferredDismissViewController()
        firstWindow.rootViewController = oldRoot

        let otherWindow = UIWindow(frame: .zero)
        otherWindow.rootViewController = UIViewController()

        let firstWindowNextRoot = UIViewController()
        let otherWindowNextRoot = UIViewController()
        var firstCompleted = false
        var otherCompleted = false

        RootInterfaceSwap.replaceRoot(of: firstWindow, with: { firstWindowNextRoot }, completion: { firstCompleted = true })
        RootInterfaceSwap.replaceRoot(of: otherWindow, with: { otherWindowNextRoot }, completion: { otherCompleted = true })

        #expect(otherWindow.rootViewController === otherWindowNextRoot)
        #expect(otherCompleted)
        #expect(!firstCompleted)
        #expect(firstWindow.rootViewController === oldRoot)

        oldRoot.finishDismissal()

        #expect(firstWindow.rootViewController === firstWindowNextRoot)
        #expect(firstCompleted)
    }

    @Test func `A dropped dismissal completion does not wedge later swaps`() {
        let testWindow = UIWindow(frame: .zero)
        let oldRoot = DeferredDismissViewController()
        testWindow.rootViewController = oldRoot

        var completed: [String] = []
        let firstRoot = UIViewController()
        let recoveryRoot = UIViewController()

        RootInterfaceSwap.replaceRoot(of: testWindow, with: { firstRoot }, completion: { completed.append("first") })
        #expect(oldRoot.dismissCallCount == 1)

        // Simulate UIKit completing the dismissal without invoking the completion block.
        oldRoot.dropDismissal()

        RootInterfaceSwap.replaceRoot(of: testWindow, with: { recoveryRoot }, completion: { completed.append("recovery") })

        #expect(testWindow.rootViewController === recoveryRoot)
        #expect(completed == ["first", "recovery"])
    }

    @Test func `A dropped dismissal followed by a new presentation does not wedge later swaps`() {
        let testWindow = UIWindow(frame: .zero)
        let oldRoot = DeferredDismissViewController()
        testWindow.rootViewController = oldRoot

        var completed: [String] = []
        let firstRoot = UIViewController()
        let secondRoot = UIViewController()

        RootInterfaceSwap.replaceRoot(of: testWindow, with: { firstRoot }, completion: { completed.append("first") })
        #expect(oldRoot.dismissCallCount == 1)

        // Simulate UIKit dropping the first dismissal and the root presenting a new modal.
        oldRoot.replacePresentedController()

        RootInterfaceSwap.replaceRoot(of: testWindow, with: { secondRoot }, completion: { completed.append("second") })
        #expect(oldRoot.dismissCallCount == 2)

        oldRoot.finishDismissal()

        #expect(testWindow.rootViewController === secondRoot)
        #expect(completed == ["first", "second"])
    }

    @Test func `A late completion from an evicted dismissal does not finish a newer swap`() {
        let testWindow = UIWindow(frame: .zero)
        let firstOldRoot = DeferredDismissViewController()
        let secondOldRoot = DeferredDismissViewController()
        testWindow.rootViewController = firstOldRoot

        let firstNextRoot = UIViewController()
        let secondNextRoot = UIViewController()
        var built: [String] = []
        var completed: [String] = []

        RootInterfaceSwap.replaceRoot(of: testWindow, with: {
            built.append("first")
            return firstNextRoot
        }, completion: {
            completed.append("first")
        })

        // Simulate an external direct root assignment before the first dismissal finishes.
        testWindow.rootViewController = secondOldRoot

        RootInterfaceSwap.replaceRoot(of: testWindow, with: {
            built.append("second")
            return secondNextRoot
        }, completion: {
            completed.append("second")
        })

        // Late completion from the first dismissal must not touch the second swap.
        firstOldRoot.finishDismissal()

        #expect(testWindow.rootViewController === secondOldRoot)
        #expect(built.isEmpty)
        #expect(completed.isEmpty)

        // Only the second dismissal installs the second root and runs the carried completions.
        secondOldRoot.finishDismissal()

        #expect(testWindow.rootViewController === secondNextRoot)
        #expect(built == ["second"])
        #expect(completed == ["first", "second"])
    }

    // MARK: - Teardown

    /// Panel to classic: the old panel root, its SwiftUI host and its sheet coordinator are freed.
    /// They own the map stops observer, which `MapRegionManager` and `RegionsService` hold only
    /// weakly. A freed panel never comes back, so this test runs into its time limit if anything
    /// keeps it.
    @Test(.timeLimit(.minutes(1)))
    func `The old map panel root is freed after switching away`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Fixtures.loadData(file: "pugetsound-weather.json")) {
            $0.url?.path.contains("/weather.json") ?? false
        }
        dataLoader.mock(data: Fixtures.loadData(file: "ondemand_services_for_location_point.json")) {
            $0.url?.path.contains("/ondemand/services-for-location") ?? false
        }
        answerEverythingElse(dataLoader)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)

        let freed = try await installPanelPresenting(application: application)

        await swap { UIViewController() }

        await freed.panel.wait()
        await freed.host.wait()
        await freed.coordinator.wait()
        #expect(application.viewRouter.mapPanelRootController == nil)
    }

    /// Classic back to the panel: the old classic tab bar root is freed too.
    @Test(.timeLimit(.minutes(1)))
    func `The old classic root is freed after switching away`() async {
        let dataLoader = MockDataLoader(testName: name)
        answerEverythingElse(dataLoader)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let classicFreed = await installPresenting(ClassicApplicationRootController(application: application))

        await swap { UIViewController() }

        await classicFreed.wait()
        #expect(application.viewRouter.rootController == nil)
    }

    // MARK: - Shared services

    /// Positive control for the test below: each change does reach a live panel's models.
    @Test(.timeLimit(.minutes(1)))
    func `A live panel's models follow region, map and bookmark changes`() async throws {
        let application = try makeObserverTestApplication()
        let panel = MapPanelRootController(application: application)
        let recorder = ObserverRecorder(panel.stopsObserver)
        let onDemandLayer = panel.layersModel.registrar.onDemandLayer

        await sendSharedServiceChanges(application)

        #expect(recorder.regionChanges == 1)
        #expect(!panel.stopsObserver.stops.isEmpty)
        // One for the bookmarks notification, one for the region change.
        #expect(recorder.bookmarkReloads == 2)
        #expect(application.locationService.delegates.contains(panel.probeController))
        // A region change rebuilds the shared map layers.
        #expect(panel.layersModel.registrar.onDemandLayer !== onDemandLayer)
    }

    /// After the switch UIKit can keep the last panel's SwiftUI graph, and its models, alive.
    /// Holding them here stands in for that: once the panel is gone, they must no longer act on
    /// the shared services they registered with.
    @Test(.timeLimit(.minutes(1)))
    func `Models that outlive their panel stop acting on shared services`() async throws {
        let application = try makeObserverTestApplication()
        let kept = makePanelKeepingModels(application: application)
        let (observer, probe) = (kept.observer, kept.probe)
        let recorder = ObserverRecorder(observer)
        let onDemandLayer = kept.layers.registrar.onDemandLayer

        await kept.panelFreed.wait()
        await sendSharedServiceChanges(application)

        #expect(recorder.regionChanges == 0)
        #expect(observer.stops.isEmpty)
        #expect(recorder.bookmarkReloads == 0)
        #expect(!application.locationService.delegates.contains(probe))
        #expect(kept.layers.registrar.onDemandLayer === onDemandLayer)
    }

    // MARK: - Helpers

    /// Builds in a separate function so the test's own frame holds no strong reference.
    private func installPresenting(_ root: UIViewController) async -> Deallocation {
        let freed = Deallocation(of: root)
        install(root)
        await present(UIViewController(), from: root)
        return freed
    }

    private func installPanelPresenting(application: Application) async throws -> PanelDeallocations {
        let panel = MapPanelRootController(application: application)
        install(panel)
        let host = try #require(panel.children.first)
        // SwiftUI presents the floating sheet in the update after the panel joins the window.
        panel.view.layoutIfNeeded()
        await nextRunLoopTurn()
        let floatingSheet = try #require(panel.presentedViewController, "SwiftUI presented the floating sheet")
        // Stands in for More and Settings, stacked on the floating sheet.
        await present(UIViewController(), from: floatingSheet)
        try #require(floatingSheet.presentedViewController != nil)
        return PanelDeallocations(
            panel: Deallocation(of: panel),
            host: Deallocation(of: host),
            coordinator: Deallocation(of: panel.coordinator)
        )
    }

    /// Starts with no stops in the map's memory or cache, so the stops can only come from the
    /// request in `sendSharedServiceChanges`.
    private func makeObserverTestApplication() throws -> Application {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) {
            $0.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }
        answerEverythingElse(dataLoader)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        try #require(application.regionsService.currentRegion?.regionIdentifier != Fixtures.tampaRegion.regionIdentifier)
        try #require(application.mapRegionManager.stops.isEmpty)
        return application
    }

    /// One change through each shared service the stops observer registers with.
    private func sendSharedServiceChanges(_ application: Application) async {
        await application.mapRegionManager.requestStops(in: MKCoordinateRegion(
            center: TestData.mockSeattleLocation.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        ))
        NotificationCenter.default.post(name: .bookmarksDidChange, object: nil)
        // The observer reloads bookmarks in a main actor task; this turn runs after it.
        await nextRunLoopTurn()
        application.regionsService.currentRegion = Fixtures.tampaRegion
    }

    private func makePanelKeepingModels(application: Application) -> KeptPanelModels {
        let panel = MapPanelRootController(application: application)
        return KeptPanelModels(
            observer: panel.stopsObserver,
            probe: panel.probeController,
            layers: panel.layersModel,
            panelFreed: Deallocation(of: panel)
        )
    }

    /// A live root, or a region change, loads whatever the app shows; none of it matters here, so
    /// every request without its own stub gets an empty "not found".
    private func answerEverythingElse(_ dataLoader: MockDataLoader) {
        dataLoader.mock(data: Data(), statusCode: 404) { _ in true }
    }

    private func install(_ root: UIViewController) {
        window.rootViewController = root
        window.makeKeyAndVisible()
    }

    private func present(_ controller: UIViewController, from presenter: UIViewController) async {
        await withCheckedContinuation { continuation in
            presenter.present(controller, animated: false) { continuation.resume() }
        }
    }

    private func swap(_ makeRoot: @escaping () -> UIViewController) async {
        await withCheckedContinuation { continuation in
            RootInterfaceSwap.replaceRoot(of: window, with: makeRoot) { continuation.resume() }
        }
    }

    /// Lets UIKit finish the current run loop turn.
    private func nextRunLoopTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

/// A root controller that holds its `dismiss(animated:completion:)` completion
/// until the test triggers it, making in-flight overlap deterministic.
private final class DeferredDismissViewController: UIViewController {
    private var fakePresented: UIViewController? = UIViewController()
    private(set) var dismissCallCount = 0
    private var pendingDismissCompletion: (() -> Void)?

    override var presentedViewController: UIViewController? {
        fakePresented
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        dismissCallCount += 1
        pendingDismissCompletion = completion
    }

    func finishDismissal() {
        fakePresented = nil
        let completion = pendingDismissCompletion
        pendingDismissCompletion = nil
        completion?()
    }

    func dropDismissal() {
        fakePresented = nil
        pendingDismissCompletion = nil
    }

    func replacePresentedController() {
        fakePresented = UIViewController()
        pendingDismissCompletion = nil
    }
}

/// Counts what a stops observer publishes.
private final class ObserverRecorder {
    private(set) var regionChanges = 0
    private(set) var bookmarkReloads = 0
    private var subscriptions = Set<AnyCancellable>()

    init(_ observer: MapStopsObserver) {
        observer.regionChanged.sink { [unowned self] _ in regionChanges += 1 }.store(in: &subscriptions)
        // `dropFirst`: `@Published` replays the current value to a new subscriber.
        observer.$bookmarks.dropFirst().sink { [unowned self] _ in bookmarkReloads += 1 }.store(in: &subscriptions)
    }
}

private struct KeptPanelModels {
    let observer: MapStopsObserver
    let probe: OnDemandProbeController
    let layers: MapPanelLayersModel
    let panelFreed: Deallocation
}

private struct PanelDeallocations {
    let panel: Deallocation
    let host: Deallocation
    let coordinator: Deallocation
}

/// Finishes when the object it watches is deallocated: a sentinel rides along as an associated
/// object, and the runtime releases it as the object goes away. Awaiting that is an event, not a
/// poll, so the test waits exactly as long as any in-flight work keeps the object alive.
private struct Deallocation {
    private let stream: AsyncStream<Void>

    init(of object: AnyObject) {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        self.stream = stream
        let sentinel = DeallocSentinel(continuation: continuation)
        objc_setAssociatedObject(object, Unmanaged.passUnretained(sentinel).toOpaque(), sentinel, .OBJC_ASSOCIATION_RETAIN)
    }

    func wait() async {
        for await _ in stream {}
    }
}

private nonisolated final class DeallocSentinel: Sendable {
    let continuation: AsyncStream<Void>.Continuation

    init(continuation: AsyncStream<Void>.Continuation) {
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
    }
}
