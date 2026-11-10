//
//  StopDeparturesBuilderTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import SwiftUI
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// A `StopViewModelEnvironment` whose bike mode, donation request and feature
/// statuses a test can set. A test `Application` never reports Obaco and push
/// as running, so without this `canAlarm` could only ever be false.
///
/// It has no current region, so `StopViewModel` skips everything gated on one:
/// persisting stop preferences, recording the stop as recent, and matching
/// saved alarms to departures. None of that is under test here.
@MainActor
private final class FakeStopEnvironment: StopViewModelEnvironment {
    let apiService: RESTAPIService?
    let obacoService: ObacoAPIService? = nil
    let pushService: PushService? = nil
    let surveyService: SurveyService
    let userDefaults: UserDefaults
    let reviewPromptPolicy: ReviewPromptPolicy
    let promptCoordinator: PromptCoordinator
    let formatters = Formatters(locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian), themeColors: .shared)

    var bikeModeEnabled = false
    var shouldRequestDonations = false
    var obacoFeatureStatus: Application.FeatureStatus = .off
    var pushFeatureStatus: Application.FeatureStatus = .off
    var userAlarms: [Alarm] = []
    var effectiveArrivalDepartureFilter: ArrivalDepartureFilter = .all

    init(userDefaults: UserDefaults, apiService: RESTAPIService?) {
        self.userDefaults = userDefaults
        self.apiService = apiService
        self.surveyService = SurveyService(apiService: nil, userDataStore: UserDefaultsStore(userDefaults: userDefaults))
        self.reviewPromptPolicy = ReviewPromptPolicy(userDefaults: userDefaults)
        self.promptCoordinator = PromptCoordinator(userDefaults: userDefaults)
    }

    func addAlarm(_ alarm: Alarm) { userAlarms.append(alarm) }
    func deleteAlarm(_ alarm: Alarm) { userAlarms.removeAll { $0 === alarm } }
    func deleteExpiredAlarms() {}
    func recordRecentStop(_ stop: Stop, region: Region) {}
    var defaultAlarmLeadTimeMinutes: Int { 10 }
    var walkingSpeedMetersPerSecond: CLLocationSpeed { 1.4 }
    var bikeSpeedMetersPerSecond: CLLocationSpeed { 4.2 }
    var effectiveTravelVelocityMetersPerSecond: CLLocationSpeed { bikeModeEnabled ? 4.2 : 1.4 }

    func stopPreferences(stopID: StopID, region: Region) -> StopPreferences { StopPreferences() }
    func setStopPreferences(_ prefs: StopPreferences, stop: Stop, region: Region) {}
    func hasStopPreferences(stopID: StopID, region: Region) -> Bool { false }
    func setArrivalDepartureFilter(_ filter: ArrivalDepartureFilter) { effectiveArrivalDepartureFilter = filter }

    var currentUserLocation: CLLocation? { nil }
    func activeProximityAlert(for stopID: StopID) -> ProximityAlert? { nil }
    func noteStopLoadFailed() {}
    var analytics: Analytics? { nil }
    var currentRegion: Region? { nil }
    var currentRegionName: String? { "Puget Sound" }
    var isCellularDataRestricted: Bool { false }
}

/// Records which `StopPageNavigationHandler` closure ran, and for which trip or alert.
@MainActor
private final class NavigationRecorder {
    struct Call: Equatable {
        let action: String
        /// The trip ID of the departure, or the alert ID, the call was made for.
        let id: String?
    }

    var calls: [Call] = []
    /// The completion `dismissDonation` was handed, run by the test when it
    /// wants the rider to have finished hiding the card.
    var pendingDismissal: (() -> Void)?

    private func record(_ action: String, _ departure: ArrivalDeparture?) {
        calls.append(Call(action: action, id: departure?.tripID))
    }

    var handler: StopPageNavigationHandler {
        StopPageNavigationHandler(
            showTrip: { self.record("showTrip", $0) },
            showScheduleForStop: { self.record("showScheduleForStop", nil) },
            showScheduleForRoute: { self.record("showScheduleForRoute", $0) },
            showWalkingDirections: {}, pillDirections: .none,
            showDirectionsToHere: nil, showDirectionsFromHere: nil,
            showAlertDetail: { self.calls.append(Call(action: "showAlertDetail", id: $0.id)) },
            showOnDemandService: { _ in },
            showBookmarkEditor: { self.record("showBookmarkEditor", $0) },
            shareTrip: { self.record("shareTrip", $0) },
            showAlarmPicker: { self.record("showAlarmPicker", $0) },
            startLiveActivity: { self.record("startLiveActivity", $0) },
            showExternalSurveyError: {}, showDonation: { self.record("showDonation", nil) },
            dismissDonation: { self.pendingDismissal = $0 },
            makeTripPreview: { self.record("makeTripPreview", $0); return AnyView(EmptyView()) },
            showRouteFilter: {}, showServiceAlerts: {}, showNearbyStops: {}, showReportProblem: {},
            toggleProximityAlert: {}, closeSheet: {}
        )
    }
}

/// The `@State` a stop page presentation owns and hands the builder as bindings.
@MainActor
private final class PageState {
    var expandedRouteID: RouteID?
    var donationHidden = false
    var pastCollapsed = false
}

/// Tests for `StopDeparturesBuilder`, which assembles the stop page's departure
/// list from a `StopViewModel` for both stop page presentations.
@MainActor
@Suite(.serialized)
final class StopDeparturesBuilderTests: OBATestCase {

    private var environment: FakeStopEnvironment!
    private var dataLoader: MockDataLoader!
    private var recorder: NavigationRecorder!
    private var state: PageState!

    override init() async throws {
        try await super.init()
        dataLoader = MockDataLoader(testName: name)
        environment = FakeStopEnvironment(userDefaults: userDefaults, apiService: buildRESTService(dataLoader: dataLoader))
        recorder = NavigationRecorder()
        state = PageState()
    }

    // MARK: - Builders

    private func makeViewModel(stopID: StopID = "1_75403", bookmarkContext: Bookmark? = nil) -> StopViewModel {
        StopViewModel(environment: environment, stopID: stopID, bookmarkContext: bookmarkContext)
    }

    private func makeBuilder(_ viewModel: StopViewModel) -> StopDeparturesBuilder {
        let state = state!
        return StopDeparturesBuilder(
            viewModel: viewModel,
            navigation: recorder.handler,
            userDefaults: userDefaults,
            onRetry: {},
            expandedRouteID: Binding(get: { state.expandedRouteID }, set: { state.expandedRouteID = $0 }),
            donationHidden: Binding(get: { state.donationHidden }, set: { state.donationHidden = $0 }),
            pastCollapsed: Binding(get: { state.pastCollapsed }, set: { state.pastCollapsed = $0 })
        )
    }

    private func sections(_ viewModel: StopViewModel, hasLoadedArrivals: Bool = true) -> StopDeparturesSections {
        let content = StopPageContent(
            stop: nil,
            allDepartures: [],
            hasLoadedArrivals: hasLoadedArrivals,
            preferences: viewModel.stopPreferences,
            isListFiltered: false,
            arrivalDepartureFilter: .all,
            isLoading: false,
            hasError: false,
            isBrokenBookmark: false
        )
        return makeBuilder(viewModel).sections(content: content, walkTime: nil)
    }

    /// `Fixtures.arrivalDeparture` takes seconds since the 2001 reference date.
    private func departure(tripID: String, minutesFromNow minutes: Int = 30) throws -> ArrivalDeparture {
        let time = Int(Date().addingTimeInterval(TimeInterval(minutes * 60)).timeIntervalSinceReferenceDate)
        return try Fixtures.arrivalDeparture(scheduledArrival: time, scheduledDeparture: time, tripID: tripID)
    }

    private func stubArrivals(file: String) {
        dataLoader.mock(data: Fixtures.loadData(file: file)) { request in
            request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
        }
    }

    private func stubArrivalsFailure(statusCode: Int) {
        dataLoader.mock(data: Data(), statusCode: statusCode) { request in
            request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
        }
    }

    // MARK: - Sections

    @Test func `Sections use the view model's sort type`() {
        let viewModel = makeViewModel()
        #expect(sections(viewModel).sortType == .time)

        viewModel.updateSortType(.route)

        #expect(sections(viewModel).sortType == .route)
    }

    @Test func `Sections follow the rider's bike mode`() {
        let viewModel = makeViewModel()
        #expect(sections(viewModel).isBikeMode == false)

        environment.bikeModeEnabled = true

        #expect(sections(viewModel).isBikeMode)
    }

    @Test func `Sections carry the stop's service alerts`() async throws {
        stubArrivals(file: "arrivals_and_departures_for_stop_mts_13353_route_and_stop_alerts.json")
        let viewModel = makeViewModel(stopID: "MTS_13353")
        #expect(sections(viewModel).serviceAlerts.isEmpty)

        await viewModel.refresh()

        // The stop-level situation in the fixture.
        #expect(sections(viewModel).serviceAlerts.map(\.id) == ["MTS_9c943ee8-d566-4cd8-8a89-a2a535ebe4fe"])
    }

    @Test func `Sections flag a bookmark whose stop is gone`() async throws {
        stubArrivalsFailure(statusCode: 404)
        let stop = try #require(try Fixtures.loadSomeStops().first)
        let bookmark = Bookmark(name: "Gone", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        let viewModel = makeViewModel(bookmarkContext: bookmark)
        #expect(sections(viewModel).isBrokenBookmark == false)

        await viewModel.refresh()
        #expect(viewModel.isBrokenBookmark)

        #expect(sections(viewModel).isBrokenBookmark)
    }

    @Test func `Sections carry the message for a failed load`() async throws {
        stubArrivalsFailure(statusCode: 500)
        let viewModel = makeViewModel()
        await viewModel.refresh()
        let message = try #require(viewModel.operationErrorMessage)

        #expect(sections(viewModel).errorText == message)
    }

    @Test func `Donation card shows only once arrivals load, donations are wanted, and the rider hasn't hidden it`() {
        let viewModel = makeViewModel()
        environment.shouldRequestDonations = true
        #expect(sections(viewModel).showsDonation)

        #expect(sections(viewModel, hasLoadedArrivals: false).showsDonation == false)

        environment.shouldRequestDonations = false
        #expect(sections(viewModel).showsDonation == false)

        environment.shouldRequestDonations = true
        state.donationHidden = true
        #expect(sections(viewModel).showsDonation == false)
    }

    // MARK: - Row actions

    /// Each action must make exactly one navigation call, the one named for it,
    /// and pass it the row's own departure.
    @Test func `Each row action calls only its own navigation, for that row's departure`() throws {
        let builder = makeBuilder(makeViewModel())
        let row = try departure(tripID: "trip_second")

        let cases: [(action: String, invoke: (DepartureRowActions) -> Void)] = [
            ("showScheduleForRoute", { $0.onSchedule() }),
            ("showBookmarkEditor", { $0.onBookmark() }),
            ("showTrip", { $0.onShowTrip() }),
            ("shareTrip", { $0.onShareTrip() }),
            ("makeTripPreview", { _ = $0.makePreview() })
        ]

        for (action, invoke) in cases {
            recorder.calls = []
            invoke(builder.makeActions(for: row))
            #expect(recorder.calls == [NavigationRecorder.Call(action: action, id: "trip_second")], "\(action)")
        }
    }

    @Test func `Row actions say whether that departure has an alarm`() throws {
        let viewModel = makeViewModel()
        let builder = makeBuilder(viewModel)
        let withAlarm = try departure(tripID: "trip_alarm")
        let withoutAlarm = try departure(tripID: "trip_plain")

        viewModel.registerAlarm(try Fixtures.loadAlarm(), for: withAlarm)

        #expect(builder.makeActions(for: withAlarm).hasAlarm)
        #expect(builder.makeActions(for: withoutAlarm).hasAlarm == false)
    }

    @Test func `Row actions allow an alarm only when the view model does`() throws {
        let viewModel = makeViewModel()
        let builder = makeBuilder(viewModel)
        let row = try departure(tripID: "trip_1")
        environment.obacoFeatureStatus = .running
        environment.pushFeatureStatus = .running
        #expect(viewModel.canCreateAlarm(for: row))
        #expect(builder.makeActions(for: row).canAlarm)

        environment.pushFeatureStatus = .off
        #expect(viewModel.canCreateAlarm(for: row) == false)
        #expect(builder.makeActions(for: row).canAlarm == false)
    }

    @Test func `Toggling the alarm on a departure without one opens the picker for it`() throws {
        let builder = makeBuilder(makeViewModel())
        let row = try departure(tripID: "trip_1")

        builder.makeActions(for: row).onAlarmToggle()

        #expect(recorder.calls == [NavigationRecorder.Call(action: "showAlarmPicker", id: "trip_1")])
    }

    /// With no Obaco service the cancel fails and the alarm stays, but the
    /// picker must not open either way.
    @Test func `Toggling the alarm on a departure that has one doesn't open the picker`() throws {
        let viewModel = makeViewModel()
        let builder = makeBuilder(viewModel)
        let row = try departure(tripID: "trip_1")
        viewModel.registerAlarm(try Fixtures.loadAlarm(), for: row)

        builder.makeActions(for: row).onAlarmToggle()

        #expect(recorder.calls.isEmpty)
    }

    // MARK: - List actions

    @Test func `Selecting a departure, an alert or the donation card opens the matching page`() throws {
        let list = sections(makeViewModel())
        let row = try departure(tripID: "trip_1")
        let data = Fixtures.loadData(file: "arrival-and-departure-for-stop-MTS_11589.json")
        let alert = try #require(try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<ArrivalDeparture>.self, from: data).references?.serviceAlerts.first)

        list.onSelectDeparture(row)
        list.onSelectAlert(alert)
        list.onDonate()

        #expect(recorder.calls == [
            NavigationRecorder.Call(action: "showTrip", id: "trip_1"),
            NavigationRecorder.Call(action: "showAlertDetail", id: alert.id),
            NavigationRecorder.Call(action: "showDonation", id: nil)
        ])
    }

    @Test func `The show-all buttons clear the route filter and the departure type filter`() {
        let viewModel = makeViewModel()
        viewModel.updateArrivalDepartureFilter(.estimatedOnly)
        #expect(viewModel.isListFiltered)
        #expect(viewModel.arrivalDepartureFilter == .estimatedOnly)
        let list = sections(viewModel)

        list.onShowAllRoutes()
        #expect(viewModel.isListFiltered == false)
        #expect(viewModel.arrivalDepartureFilter == .estimatedOnly)

        list.onShowAllDepartureTypes()
        #expect(viewModel.arrivalDepartureFilter == .all)
    }

    @Test func `Changing the mode collapses the open route, saves the choice and re-sorts`() {
        let viewModel = makeViewModel()
        state.expandedRouteID = "1_100"
        #expect(viewModel.stopPreferences.sortType == .time)

        sections(viewModel).onChangeMode(.route)

        #expect(state.expandedRouteID == nil)
        #expect(userDefaults.string(forKey: StopPageLifecycleKeys.lastUsedStopSort) == "route")
        #expect(viewModel.stopPreferences.sortType == .route)
    }

    @Test func `Tapping a route opens it, another route switches, and the open route closes`() {
        let list = sections(makeViewModel())

        list.onToggleRoute("1_100")
        #expect(state.expandedRouteID == "1_100")

        list.onToggleRoute("1_200")
        #expect(state.expandedRouteID == "1_200")

        list.onToggleRoute("1_200")
        #expect(state.expandedRouteID == nil)
    }

    /// The rider can cancel the dismiss sheet, so the card stays until they
    /// actually hide it.
    @Test func `Closing the donation card hides it only once the rider confirms`() {
        let list = sections(makeViewModel())

        list.onDonationClose()
        #expect(state.donationHidden == false)

        let confirm = recorder.pendingDismissal
        #expect(confirm != nil)
        confirm?()

        #expect(state.donationHidden)
    }
}
