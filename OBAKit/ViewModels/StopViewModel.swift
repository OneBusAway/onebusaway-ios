//
//  StopViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Combine
import CoreLocation
import UserNotifications
import OBAKitCore

/// Shared ViewModel for the stop arrivals/departures screen.
///
/// Consumed by `StopViewController` (UIKit, via Combine `sink`) and by
/// future `StopDetailSheet` (SwiftUI, via `@StateObject`).
/// Contains no UIKit or SwiftUI imports.
@MainActor
class StopViewModel: ObservableObject {

    // MARK: - Published State

    /// The stop being displayed.
    @Published private(set) var stop: Stop?

    /// The survey to render as an inline hero card on this stop, or `nil` for no card.
    /// Recomputed on every stop refresh and after every survey-list refresh — the
    /// `@Published` re-fires per assignment (even nil→nil) so the VC's `$currentSurvey`
    /// sink is the sole driver of survey-row reloads.
    @Published private(set) var currentSurvey: Survey?

    /// Whether the inline donation-request card should be offered on this stop.
    /// Mirrors `DonationsManager.shouldRequestDonations`; read by the SwiftUI Stop
    /// page, which has no `Application` reference of its own. Not `@Published` — the
    /// page re-reads it on the view model's routine refresh churn, and the explicit
    /// dismiss path hides the card immediately via local view state.
    var shouldRequestDonations: Bool {
        application.donationsManager.shouldRequestDonations
    }

    /// Emits when the inline hero answer succeeds but the survey has remaining
    /// questions. Consumers present the full survey screen with the supplied
    /// `heroResponseID` so the hero isn't re-submitted on retry.
    var presentFullSurvey: AnyPublisher<FullSurveyPresentation, Never> {
        presentFullSurveySubject.eraseToAnyPublisher()
    }
    private let presentFullSurveySubject = PassthroughSubject<FullSurveyPresentation, Never>()

    /// Emits when the inline hero submission fails. Consumers show the alert.
    var surveySubmissionError: AnyPublisher<Error, Never> {
        surveySubmissionErrorSubject.eraseToAnyPublisher()
    }
    private let surveySubmissionErrorSubject = PassthroughSubject<Error, Never>()

    /// Payload for `presentFullSurvey`: the survey, the hero submission id (so
    /// the full screen skips the hero), and the stop coordinate at submission time.
    struct FullSurveyPresentation {
        let survey: Survey
        let heroResponseID: String
        let stopLocation: CLLocationCoordinate2D?
    }

    /// The arrivals/departures fetched from the server.
    @Published private(set) var stopArrivals: StopArrivals?

    /// `true` while a network request is in-flight.
    @Published private(set) var isLoading = false

    /// The last time data was successfully loaded. Not `@Published`: no consumer observes
    /// it directly. It feeds `statusText` (via `updateStatus()`, called right after each
    /// assignment) and the `shouldRefresh` threshold check — both internal reads.
    private(set) var lastUpdated: Date?

    /// A human-readable status string (e.g. "Updated 2 min ago").
    @Published private(set) var statusText: String = ""

    /// Non-nil when a network error occurred.
    @Published private(set) var operationError: Error?

    /// `true` when a bookmark's stop ID no longer resolves.
    @Published private(set) var isBrokenBookmark = false

    /// User-saved preferences for this stop (sort order, hidden routes).
    @Published private(set) var stopPreferences: StopPreferences

    /// `true` when the arrival list should be filtered to the user's preferences.
    @Published var isListFiltered: Bool = true

    /// How many minutes of past arrivals to load.
    let minutesBefore: UInt = 5

    /// How many minutes of future arrivals to load. Increased by "Load More".
    @Published private(set) var minutesAfter: UInt

    /// The time window has been extended at least once and there are still no arrivals,
    /// so auto-extension is exhausted (capped at 12 h).
    @Published private(set) var isLoadMoreExhausted = false

    /// Alarms owned by this stop's departures, keyed by `ArrivalDeparture.id`.
    /// All four alarm entry points (swipe, pill, row icon, trip panel) read and
    /// write through this single index (§4.7).
    @Published private(set) var alarmsByDepartureID: [String: Alarm] = [:]

    /// Non-nil after an alarm create/cancel fails; consumer shows a toast/alert.
    @Published private(set) var alarmError: Error?

    /// Set `true` when the user attempts to create an alarm but notification
    /// permission is already `.denied`; the consumer presents Settings guidance
    /// and then calls `clearAlarmPermissionDenied()`.
    @Published private(set) var alarmPermissionDenied = false

    /// Departure ids with an in-flight `setAlarm`, so a double-tap can't create a
    /// duplicate alarm while the first create is suspended (MainActor-serialized,
    /// so a plain `Set` needs no further synchronization).
    private var alarmSetsInFlight: Set<String> = []

    /// Cache for trip-panel approach timelines, invalidated on each refresh.
    private var approachCache: [String: TripDetails] = [:]

    // MARK: - Init Context

    /// Optional bookmark that opened this stop view.
    var bookmarkContext: Bookmark?

    /// Transfer context, when the stop was opened as a transfer destination.
    var transferContext: TransferContext?

    // MARK: - Private

    private let application: Application
    let stopID: StopID

    private let surveyOrchestrator: SurveyOrchestrator
    private var heroSubmitInFlight: Bool = false

    private static let defaultMinutesAfter: UInt = 35
    private static let timerInterval: TimeInterval = 15
    private static let refreshThreshold: TimeInterval = 30

    private var refreshTimer: Timer?
    private var statusTimer: Timer?

    /// Gates one-shot work that should run only on the first successful fetch per VM lifetime:
    /// analytics, recent-stops recording, and the "all routes hidden" filter invariant.
    private var hasPerformedInitialStopSetup = false

    // MARK: - Init

    init(
        application: Application,
        stopID: StopID,
        stop: Stop? = nil,
        bookmarkContext: Bookmark? = nil,
        transferContext: TransferContext? = nil
    ) {
        self.application = application
        self.stopID = stopID
        self.stop = stop
        self.bookmarkContext = bookmarkContext
        self.transferContext = transferContext
        self.minutesAfter = StopViewModel.defaultMinutesAfter
        self.surveyOrchestrator = SurveyOrchestrator(surveyService: application.surveyService)

        if let currentRegion = application.currentRegion {
            self.stopPreferences = application.stopPreferencesDataStore.preferences(stopID: stopID, region: currentRegion)
        } else {
            self.stopPreferences = StopPreferences()
        }
    }

    deinit {
        refreshTimer?.invalidate()
        statusTimer?.invalidate()
    }

    // MARK: - Lifecycle

    /// Call from `viewWillAppear` / `.task`.
    func start() async {
        startStatusTimer()
        startAutoRefresh()
        await refresh()
    }

    /// Call from `viewWillDisappear` / `.onDisappear`.
    func deactivate() {
        stopAutoRefresh()
        stopStatusTimer()
    }

    // MARK: - Data Loading

    /// Fetches fresh arrivals/departures from the server.
    ///
    /// When the response is empty and the time window has room to grow, `refresh()`
    /// recurses linearly via `loadMore(minutes:)` after clearing `isLoading`, walking
    /// the window upward until arrivals appear or the 12 h cap is hit. The recursion
    /// is intentionally in-scope so the `!isLoading` ordering is expressed in code,
    /// not in a comment.
    func refresh() async {
        guard !isLoading, let apiService = application.apiService else { return }
        isLoading = true

        var pendingExtensionMinutes: UInt?

        do {
            let result = try await apiService.getArrivalsAndDeparturesForStop(
                id: stopID,
                minutesBefore: minutesBefore,
                minutesAfter: minutesAfter
            ).entry

            if let loadedStop = result.stop {
                applySuccessfulFetch(stop: loadedStop, arrivals: result)
                performInitialStopSetupIfNeeded(for: loadedStop)

                if result.arrivalsAndDepartures.isEmpty {
                    pendingExtensionMinutes = pendingAutoExtensionAmount()
                }
            }
        } catch APIError.requestNotFound {
            operationError = nil
            isBrokenBookmark = bookmarkContext != nil
        } catch {
            operationError = error
        }

        isLoading = false

        if let additionalMinutes = pendingExtensionMinutes {
            await loadMore(minutes: additionalMinutes)
        }
    }

    private func applySuccessfulFetch(stop: Stop, arrivals: StopArrivals) {
        operationError = nil
        isBrokenBookmark = false
        lastUpdated = Date()
        updateStatus()
        // Guard the @Published re-emit. The same VM is bound to a single stopID for
        // its lifetime, so `stop` only meaningfully changes when the server returns
        // new routes/wheelchair info — re-emitting on every refresh would re-run
        // the VC's title/applyData/configureTabBarButtons sink for no reason.
        if self.stop != stop {
            self.stop = stop
        }
        stopArrivals = arrivals
        approachCache.removeAll()
        rebuildAlarmIndex()
        recomputeCurrentSurvey()
    }

    /// Runs exactly once per VM lifetime on the first successful fetch:
    /// records the stop in recents, fires the `stop_viewed` analytics event, and
    /// re-enforces the "all routes hidden → drop the filter" invariant so a
    /// returning user doesn't land on an empty list.
    private func performInitialStopSetupIfNeeded(for stop: Stop) {
        guard !hasPerformedInitialStopSetup else { return }
        hasPerformedInitialStopSetup = true

        if let region = application.currentRegion {
            recordRecentStop(stop, region: region)
            reportStopViewed(stop)
        }
        disableFilterIfAllRoutesHidden()
        // Surveys don't change between auto-refreshes; fetch once per stop entry,
        // alongside the other first-fetch-only side effects above.
        refreshSurveys()
    }

    private func refreshSurveys() {
        // `refreshSurveys` records failures on the orchestrator's `lastError`
        // rather than rethrowing. Skip the recompute when it's set so a failed
        // fetch doesn't overwrite the current card. A cooldown-skipped fetch
        // after a prior *success* still recomputes (lastError stays nil);
        // after a prior *failure*, lastError is still set so the recompute is
        // skipped — by then `applySuccessfulFetch` will have already run a
        // recompute on the current survey list, so the card state is still
        // correct.
        Task { [weak self] in
            guard let self else { return }
            await self.surveyOrchestrator.refreshSurveys()
            guard self.surveyOrchestrator.lastError == nil else { return }
            self.recomputeCurrentSurvey()
        }
    }

    // MARK: - Inline Hero Survey

    /// Updates `currentSurvey` to the survey applicable for this stop right now,
    /// or `nil` if the gate is closed or no survey matches. Called whenever the
    /// stop is refreshed or the survey list is reloaded.
    private func recomputeCurrentSurvey() {
        guard surveyOrchestrator.isEligible(), let stop else {
            currentSurvey = nil
            return
        }
        let routeIDs = stop.routes.map { $0.id }
        currentSurvey = surveyOrchestrator.findStopSurvey(stopID: stopID, routeIDs: routeIDs)
    }

    /// Submits the hero answer for the currently displayed survey. On success
    /// either clears the card (no remaining questions) or emits
    /// `presentFullSurvey` for the consumer to push the full survey screen.
    /// Errors are surfaced on `surveySubmissionError`.
    func submitHeroAnswer(_ answer: String, stopLocation: CLLocationCoordinate2D?) async {
        guard !heroSubmitInFlight,
              let survey = currentSurvey,
              survey.heroQuestion != nil
        else { return }

        heroSubmitInFlight = true
        defer { heroSubmitInFlight = false }

        do {
            let outcome = try await surveyOrchestrator.submitHero(
                survey: survey,
                answer: answer,
                stopID: stopID,
                stopLocation: stopLocation
            )

            switch outcome {
            case .completed:
                currentSurvey = nil
            case .needsRemainingQuestions(let heroResponseID):
                // Clear the card before handing off to the full-survey screen so
                // a re-tap can't re-submit the hero question while the modal is
                // being presented. The card reappears on the next refresh only
                // if the survey is still applicable.
                currentSurvey = nil
                presentFullSurveySubject.send(.init(
                    survey: survey,
                    heroResponseID: heroResponseID,
                    stopLocation: stopLocation
                ))
            }
        } catch {
            Logger.error("Survey \(survey.id) hero submission failed: \(error)")
            surveySubmissionErrorSubject.send(error)
        }
    }

    /// Dismisses the currently displayed survey card and pushes the next
    /// reminder out. No-op when there is no current survey.
    func dismissCurrentSurvey() {
        guard let survey = currentSurvey else { return }
        surveyOrchestrator.dismiss(survey)
        currentSurvey = nil
    }

    /// Launches the external survey for `survey` (or the current one if `nil`).
    /// The launcher marks the survey completed only when the system actually
    /// opens the URL; on success we recompute the card so it drops from view.
    func launchExternalSurvey(
        _ survey: Survey? = nil,
        onSuccess: @escaping () -> Void = {},
        onFailure: @escaping () -> Void = {}
    ) {
        guard let target = survey ?? currentSurvey else { return }
        let launcher = ExternalSurveyLauncher(surveyService: application.surveyService)
        launcher.launch(
            survey: target,
            stop: stop,
            onSuccess: { [weak self] in
                self?.recomputeCurrentSurvey()
                onSuccess()
            },
            onFailure: onFailure
        )
    }

    /// Extends the time window and reloads data. Call when the user taps "Load More".
    func loadMoreDepartures() async {
        await loadMore(minutes: 30)
    }

    // MARK: - Preferences

    /// Persists updated stop preferences and re-renders the list.
    func updateStopPreferences(_ prefs: StopPreferences) {
        stopPreferences = prefs
        guard let stop = stop, let region = application.currentRegion else { return }
        application.stopPreferencesDataStore.set(stopPreferences: prefs, stop: stop, region: region)
        disableFilterIfAllRoutesHidden()
    }

    /// Updates the sort type preference.
    func updateSortType(_ sortType: StopSort) {
        var prefs = stopPreferences
        prefs.sortType = sortType
        updateStopPreferences(prefs)
    }

    /// Saves alarm creation to the user data store.
    func recordAlarmCreated(_ alarm: Alarm) {
        application.userDataStore.add(alarm: alarm)
    }

    /// Returns whether an alarm can be created for the given arrival/departure.
    func canCreateAlarm(for arrivalDeparture: ArrivalDeparture) -> Bool {
        guard
            application.features.obaco == .running,
            application.features.push == .running
        else { return false }
        return arrivalDeparture.arrivalDepartureMinutes > 1
    }

    // MARK: - Private Helpers

    private func loadMore(minutes: UInt) async {
        let cappedMinutes = min(minutesAfter + minutes, 720)
        minutesAfter = cappedMinutes

        if cappedMinutes >= 720 {
            isLoadMoreExhausted = true
        }

        await refresh()
    }

    /// Returns the next time-window increment for empty-result auto-extension,
    /// or `nil` if the window is already at the 12 h cap. Flips
    /// `isLoadMoreExhausted` when the cap is reached.
    private func pendingAutoExtensionAmount() -> UInt? {
        guard minutesAfter < 720 else {
            isLoadMoreExhausted = true
            return nil
        }
        return minutesAfter < 60 ? 60 : minutesAfter < 240 ? 60 : 120
    }

    private func recordRecentStop(_ stop: Stop, region: Region) {
        application.userDataStore.addRecentStop(stop, region: region)
    }

    private func reportStopViewed(_ stop: Stop) {
        application.analytics?.reportStopViewed(
            name: stop.name,
            id: stop.id,
            stopDistance: analyticsDistanceToStop(stop)
        )
    }

    private func disableFilterIfAllRoutesHidden() {
        guard isListFiltered, let stop = stop else { return }
        let allHidden = stop.routes.allSatisfy { stopPreferences.hiddenRoutes.contains($0.id) }
        if allHidden { isListFiltered = false }
    }

    private func analyticsDistanceToStop(_ stop: Stop) -> String {
        guard let userLocation = application.locationService.currentLocation else {
            return "User Distance: 03200-INFINITY"
        }
        let distance = userLocation.distance(from: stop.location)
        switch distance {
        case ..<50:   return "User Distance: 00000-00050m"
        case ..<100:  return "User Distance: 00050-00100m"
        case ..<200:  return "User Distance: 00100-00200m"
        case ..<400:  return "User Distance: 00200-00400m"
        case ..<800:  return "User Distance: 00400-00800m"
        case ..<1600: return "User Distance: 00800-01600m"
        case ..<3200: return "User Distance: 01600-03200m"
        default:      return "User Distance: 03200-INFINITY"
        }
    }

    // MARK: - Auto-Refresh Timer

    private func startAutoRefresh() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: StopViewModel.timerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.shouldRefresh else { return }
                await self.refresh()
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Exposed (rather than `private`) so tests can assert the threshold behavior
    /// without spinning the auto-refresh timer.
    var shouldRefresh: Bool {
        guard let lastUpdated else { return true }
        return abs(lastUpdated.timeIntervalSinceNow) > StopViewModel.refreshThreshold
    }

    // MARK: - Status Timer

    private func startStatusTimer() {
        guard statusTimer == nil else { return }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatus()
            }
        }
    }

    private func stopStatusTimer() {
        statusTimer?.invalidate()
        statusTimer = nil
    }

    private func updateStatus() {
        guard let lastUpdated else {
            statusText = ""
            return
        }
        statusText = String(format: Strings.updatedAtFormat, application.formatters.timeAgoInWords(date: lastUpdated))
    }

    // MARK: - Stop Page: Walk Time

    /// Walk time from the user's current location to this stop; the single
    /// source for the header chip and the chronological walk line (§4.5).
    var walkTime: WalkTimeInfo? {
        WalkTimeInfo.compute(
            from: application.locationService.currentLocation,
            to: stop?.location,
            speedMetersPerSecond: application.userDataStore.walkingSpeedMetersPerSecond
        )
    }

    // MARK: - Stop Page: Alarms

    var defaultAlarmLeadTime: Int {
        application.userDataStore.defaultAlarmLeadTimeMinutes
    }

    func alarm(for arrivalDeparture: ArrivalDeparture) -> Alarm? {
        alarmsByDepartureID[arrivalDeparture.id]
    }

    /// Minutes-before-departure for a persisted alarm, derived from its dates.
    func alarmLeadTimeMinutes(_ alarm: Alarm) -> Int {
        guard let tripDate = alarm.tripDate, let alarmDate = alarm.alarmDate else {
            return AlarmLeadTime.defaultMinutes
        }
        return max(AlarmLeadTime.minimumMinutes, Int(round(tripDate.timeIntervalSince(alarmDate) / 60.0)))
    }

    func setAlarm(for arrivalDeparture: ArrivalDeparture, leadTimeMinutes: Int) async {
        guard
            canCreateAlarm(for: arrivalDeparture),
            !alarmSetsInFlight.contains(arrivalDeparture.id),
            let obacoService = application.obacoService,
            let pushService = application.pushService,
            let region = application.currentRegion,
            let minutes = AlarmLeadTime.clamped(leadTimeMinutes, minutesUntilDeparture: arrivalDeparture.arrivalDepartureMinutes)
        else { return }

        // Reserve this departure before the first `await` so a double-tap can't
        // slip a second create through while the permission/network work is
        // suspended. The check-then-insert is atomic on the MainActor.
        alarmSetsInFlight.insert(arrivalDeparture.id)
        defer { alarmSetsInFlight.remove(arrivalDeparture.id) }

        // Already-denied notification permission is a dead end for departure
        // alarms: pushID() can't yield a deliverable id. Surface Settings
        // guidance instead. (.notDetermined falls through so pushID() triggers
        // the first-time system prompt.)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .denied {
            alarmPermissionDenied = true
            return
        }

        do {
            let userPushID = await pushService.pushID()
            let alarm = try await obacoService.postAlarm(minutesBefore: minutes, arrivalDeparture: arrivalDeparture, userPushID: userPushID)
            alarm.deepLink = ArrivalDepartureDeepLink(arrivalDeparture: arrivalDeparture, regionID: region.regionIdentifier)
            alarm.set(tripDate: arrivalDeparture.arrivalDepartureDate, alarmOffset: minutes)
            recordAlarmCreated(alarm)
            alarmsByDepartureID[arrivalDeparture.id] = alarm
            alarmError = nil
        } catch {
            Logger.error("Alarm create failed for \(arrivalDeparture.id): \(error)")
            alarmError = error
        }
    }

    func cancelAlarm(for arrivalDeparture: ArrivalDeparture) async {
        guard let alarm = alarm(for: arrivalDeparture) else { return }
        // Optimistic removal; restore on failure.
        alarmsByDepartureID[arrivalDeparture.id] = nil
        do {
            if let obacoService = application.obacoService {
                try await obacoService.deleteAlarm(url: alarm.url)
            } else {
                Logger.error("Cancelled alarm locally but obacoService is unavailable; server alarm \(alarm.url) may still fire")
            }
            application.userDataStore.delete(alarm: alarm)
            // A refresh that landed mid-await could have re-inserted this entry
            // (rebuildAlarmIndex ran while the persisted alarm was still present);
            // re-assert the removal now that the alarm is actually deleted.
            alarmsByDepartureID[arrivalDeparture.id] = nil
            alarmError = nil
        } catch {
            Logger.error("Alarm cancel failed for \(arrivalDeparture.id): \(error)")
            alarmsByDepartureID[arrivalDeparture.id] = alarm
            alarmError = error
        }
    }

    /// Toggle entry point shared by all four alarm surfaces (§4.7).
    func toggleAlarm(for arrivalDeparture: ArrivalDeparture) async {
        if alarm(for: arrivalDeparture) != nil {
            await cancelAlarm(for: arrivalDeparture)
        } else {
            await setAlarm(for: arrivalDeparture, leadTimeMinutes: defaultAlarmLeadTime)
        }
    }

    /// Resets the permission-denied flag after the consumer has presented its
    /// Settings-guidance alert, so a later already-denied attempt re-fires the
    /// binding.
    func clearAlarmPermissionDenied() {
        alarmPermissionDenied = false
    }

    /// Obaco has no update endpoint: change = delete + re-post. Proceeds only
    /// when the old alarm is actually gone (a failed delete rolls it back into
    /// the index), so a stale `alarmError` from an earlier operation can't
    /// block the change.
    func changeAlarm(for arrivalDeparture: ArrivalDeparture, leadTimeMinutes: Int) async {
        await cancelAlarm(for: arrivalDeparture)
        guard alarm(for: arrivalDeparture) == nil else { return }
        await setAlarm(for: arrivalDeparture, leadTimeMinutes: leadTimeMinutes)
    }

    /// Rebuilds the departure-id → alarm index by matching each persisted
    /// alarm's deep link against the current departures. Called after each
    /// successful fetch so expired/foreign alarms fall out naturally.
    private func rebuildAlarmIndex() {
        guard let region = application.currentRegion,
              let departures = stopArrivals?.arrivalsAndDepartures
        else {
            alarmsByDepartureID = [:]
            return
        }
        // Fast path: `alarms` JSON-decodes the persisted store on every access.
        // With nothing persisted there's no expiry to run and no match to make,
        // so bail before touching `deleteExpiredAlarms()`.
        guard !application.userDataStore.alarms.isEmpty else {
            alarmsByDepartureID = [:]
            return
        }
        application.userDataStore.deleteExpiredAlarms()
        // Re-read the pruned set once, out of the loop (another decode per access).
        let alarms = application.userDataStore.alarms
        var index: [String: Alarm] = [:]
        for departure in departures {
            let candidate = ArrivalDepartureDeepLink(arrivalDeparture: departure, regionID: region.regionIdentifier)
            if let match = alarms.first(where: { $0.deepLink == candidate }) {
                index[departure.id] = match
            }
        }
        alarmsByDepartureID = index
    }

    // MARK: - Stop Page: Approach Timeline

    /// Trip details backing the trip panel's approach timeline. Fetched on
    /// panel open, cached until the next refresh, live trips only (§4.1).
    func approachTripDetails(for arrivalDeparture: ArrivalDeparture) async -> TripDetails? {
        guard arrivalDeparture.predicted, let apiService = application.apiService else { return nil }
        if let cached = approachCache[arrivalDeparture.tripID] { return cached }
        do {
            let details = try await apiService.getTrip(
                tripID: arrivalDeparture.tripID,
                vehicleID: arrivalDeparture.vehicleID,
                serviceDate: arrivalDeparture.serviceDate
            ).entry
            approachCache[arrivalDeparture.tripID] = details
            return details
        } catch {
            return nil // panel silently omits the timeline on failure
        }
    }
}
