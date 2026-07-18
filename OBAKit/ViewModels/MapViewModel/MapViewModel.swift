//
//  MapViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Combine
import CoreLocation
import OBAKitCore

/// The selected base map style. UIKit maps `.standard` → `MKMapType.mutedStandard`
/// and `.hybrid` → `MKMapType.hybrid`; SwiftUI can map directly to `MapStyle`.
/// Kept MapKit-free so this VM stays usable from both UIKit and SwiftUI hosts.
enum MapBaseType {
    case standard
    case hybrid
}

/// Shared ViewModel for the main map screen.
///
/// Consumed by `MapViewController` (UIKit, via Combine `sink`) and by
/// `MapPanelRootView` (SwiftUI, via `@StateObject`).
/// Contains no UIKit, MapKit, or SwiftUI imports.
///
/// Subclasses NSObject so it can adopt `LocationServiceDelegate`, which is
/// `@objc` (declared in OBAKitCore for legacy Obj-C interop). Other map
/// delegates (`MapRegionDelegate`, `MapPanelDelegate`) intentionally stay
/// on `MapViewController` because their callbacks are UIKit/router-shaped,
/// not state-shaped.
@MainActor
class MapViewModel: NSObject, ObservableObject, LocationServiceDelegate {

    // MARK: - Published State

    /// View-ready weather data, rebuilt only when `loadWeather()` finishes —
    /// SwiftUI body re-reads don't pay the formatting cost. The raw
    /// `WeatherForecast` model isn't surfaced; reintroduce it on demand if a
    /// future consumer needs it.
    @Published private(set) var weatherDisplay: WeatherDisplay?

    /// `true` when the map is zoomed out too far to load stops.
    /// Written only through `updateZoomWarning(_:)` so the VC's `MapRegionDelegate`
    /// callback routes through the VM rather than mutating published state directly.
    @Published private(set) var showZoomWarning = false

    /// The currently selected base map type (standard vs. hybrid).
    /// Persistence is owned by `toggleMapType()`, which writes through
    /// `MapRegionManager`; the UIKit `$mapType` sink only mirrors the value
    /// onto MapKit and refreshes its toolbar icon.
    @Published private(set) var mapType: MapBaseType

    /// The current location authorization status. Used by the UI to show/hide location controls.
    @Published private(set) var locationAuthStatus: CLAuthorizationStatus

    /// The current location accuracy authorization (full vs. reduced). Tracked
    /// as published state — rather than read live from `locationService` — so
    /// the top status pill re-evaluates when accuracy changes without the
    /// coarse `locationAuthStatus` changing (e.g. after "Allow Once").
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization

    // MARK: - Survey Prompt

    /// Emits the survey to present when one is eligible and found. One-shot per
    /// session; observers handle presentation (modal sheet, fullScreenCover, etc.).
    var surveyToPresent: AnyPublisher<Survey, Never> {
        surveyToPresentSubject.eraseToAnyPublisher()
    }
    private let surveyToPresentSubject = PassthroughSubject<Survey, Never>()

    private var hasShownSurveyThisSession = false
    private let surveyOrchestrator: SurveyOrchestrator

    // MARK: - Private

    private let application: Application
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(application: Application, initialMapType: MapBaseType = .standard) {
        self.application = application
        self.mapType = initialMapType
        self.locationAuthStatus = application.locationService.authorizationStatus
        self.accuracyAuthorization = application.locationService.accuracyAuthorization
        self.surveyOrchestrator = SurveyOrchestrator(surveyService: application.surveyService)
        super.init()
        application.locationService.addDelegate(self)

        // Keep `mapType` in step with `MapRegionManager.userSelectedMapType`,
        // which UIKit surfaces (the toolbar toggle) and any future consumer
        // may mutate. `UserDefaults.didChangeNotification` is coarse — it
        // fires for any defaults change — but the cost is a single read of an
        // integer-backed value and a comparison, and it avoids exposing the
        // private storage key from `MapRegionManager`.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: application.userDefaults)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncMapTypeFromRegionManager()
            }
            .store(in: &cancellables)
    }

    isolated deinit {
        application.locationService.removeDelegate(self)
    }

    /// Re-reads the persisted map type and mirrors it onto `mapType` when it
    /// differs. No-op when the persisted value already matches — this is the
    /// hot path for `UserDefaults.didChangeNotification` fan-out, so avoid a
    /// republish on every unrelated defaults write.
    private func syncMapTypeFromRegionManager() {
        let persisted = MapBaseType(application.mapRegionManager.userSelectedMapType)
        if persisted != mapType {
            mapType = persisted
        }
    }

    // MARK: - Lifecycle

    /// Call from `viewDidAppear` / `.task`.
    func start() {
        reloadBookmarks()
        Task { [weak self] in await self?.loadWeather() }
    }

    // MARK: - Weather

    /// `true` when the host should render any weather UI. Mirrors the gate at
    /// `MapViewController.toolbar` so UIKit and SwiftUI agree on availability.
    var isWeatherFeatureAvailable: Bool {
        application.features.obaco == .running
    }

    func loadWeather() async {
        guard let apiService = application.obacoService else {
            // Clear so an out-of-region transition doesn't leave a stale
            // forecast on screen — this is configuration-shaped (no Obaco for
            // this region), so the button SHOULD disappear.
            weatherDisplay = nil
            return
        }
        do {
            let forecast = try await apiService.getWeather()
            weatherDisplay = WeatherDisplay(forecast: forecast, locale: application.locale)
        } catch {
            // Keep the last-known forecast on a transient failure (network
            // blip, 5xx during scene reactivation) so the floating button
            // doesn't flicker out and come back. The next successful refresh
            // — `start()`, `onAppBecameActive`, or the next manual trigger —
            // will overwrite this with fresh data; until then a slightly
            // stale forecast is better than a missing UI element.
            Logger.error("Failed to load weather: \(error)")
        }
    }

    // MARK: - Zoom Warning

    /// Updates the "zoomed out too far" banner state. Called by the VC's
    /// `MapRegionDelegate.mapRegionManagerShowZoomInStatus` callback.
    func updateZoomWarning(_ show: Bool) {
        showZoomWarning = show
    }

    // MARK: - Zoom Constants

    /// Latitude/longitude span used when the user taps the "Zoom in for stops"
    /// affordance. Shared with `MapViewController.didTapZoomInForStops` and
    /// `MapStatusPill` so both surfaces zoom to the same target.
    static let zoomInForStopsSpan: Double = 0.01

    /// Returns the zoom level to use when centering on the user's current
    /// location. Full accuracy zooms tight (17); reduced accuracy zooms out
    /// (11) so the ~1km approximation cell fits comfortably in view.
    ///
    /// Reads accuracy live from `locationService` rather than the cached
    /// `@Published accuracyAuthorization`: iOS does not reliably deliver
    /// `locationManagerDidChangeAuthorization` for a temporary full-accuracy
    /// grant ("Allow Once"), so the cache can still read `.reducedAccuracy`
    /// when the user taps "center on my location" right after granting. This
    /// is an imperative one-shot read (not reactive display), so a live read
    /// is correct and can't go stale.
    func zoomLevelForCurrentLocation() -> Int {
        return application.locationService.accuracyAuthorization == .reducedAccuracy ? 11 : 17
    }

    // MARK: - Top Pill State

    /// What the top-center map-status pill should currently show. Zoom warning
    /// wins over permission state, mirroring `MapStatusView.configure(for:zoomInStatus:)`.
    enum TopPillState: Equatable {
        case hidden
        case zoomInForStops
        case notDetermined
        case locationServicesOff
        /// Location services can't be changed by the user (MDM/parental
        /// restriction) or the OS reports a status we don't recognize. The
        /// pill shows a non-actionable warning — tapping opens no alert,
        /// because there is nothing the user can do in Settings to resolve it.
        /// Mirrors the old `MapStatusView.LocationState.locationServicesUnavailable`.
        case locationServicesUnavailable
        case impreciseLocation
    }

    var topPillState: TopPillState {
        if showZoomWarning { return .zoomInForStops }
        switch locationAuthStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .locationServicesOff
        case .restricted:
            // A restricted user cannot lift the restriction in Settings, so a
            // "Turn On in Settings" prompt would be a dead end. Surface a
            // visible-but-non-actionable pill instead.
            return .locationServicesUnavailable
        case .authorizedAlways, .authorizedWhenInUse:
            return accuracyAuthorization == .reducedAccuracy ? .impreciseLocation : .hidden
        @unknown default:
            // A future Apple-introduced denied-like status must still surface a
            // visible pill rather than silently hiding the location status.
            return .locationServicesUnavailable
        }
    }

    // MARK: - Location Permission Helpers

    /// Prompts the user for when-in-use location authorization. Thin wrapper so
    /// SwiftUI callers don't need to reach into `application.locationService`.
    func requestLocationAuthorization() {
        application.locationService.requestInUseAuthorization()
    }

    /// Requests a one-shot full-accuracy elevation. `purposeKey` must match a
    /// `NSLocationTemporaryUsageDescriptionDictionary` entry in the host app's
    /// Info.plist (existing key: `MapStatusView`).
    func requestTemporaryFullAccuracy(purposeKey: String) {
        application.locationService.requestTemporaryFullAccuracyAuthorization(withPurposeKey: purposeKey)
    }

    // MARK: - Map Type

    /// Toggles between the standard and hybrid base map types and persists
    /// the choice through `MapRegionManager`. The UIKit path used to persist
    /// this in its `$mapType` Combine sink; owning it here means SwiftUI-only
    /// sessions persist too, and both paths share one write.
    func toggleMapType() {
        let next: MapBaseType = mapType == .standard ? .hybrid : .standard
        mapType = next
        application.mapRegionManager.userSelectedMapType = next.mkMapType
    }

    // MARK: - Bookmarks

    func reloadBookmarks() {
        guard let region = application.currentRegion else { return }
        application.mapRegionManager.bookmarks = application.userDataStore.findBookmarks(in: region)
    }

    // MARK: - App Lifecycle (EC12)

    /// Call when the app becomes active after a background stint.
    /// Re-fetches weather so the display stays fresh without relying on UIKit notification names.
    func onAppBecameActive() {
        Task { [weak self] in await self?.loadWeather() }
    }

    // MARK: - Survey Prompt

    /// Checks once per session whether a map survey should be presented. On
    /// the first eligible hit emits the survey on `surveyToPresent`; the
    /// consumer presents it and reports back via
    /// `didPresentSurveyPrompt(_:presented:)` so the reminder advances only
    /// on confirmed presentation, and the session flag rolls back if the
    /// presenter dropped the survey.
    func checkForSurveyPrompt() async {
        guard !hasShownSurveyThisSession else { return }
        guard surveyOrchestrator.isEligible() else { return }

        await surveyOrchestrator.refreshSurveys()

        // Skip the prompt if the refresh itself failed. `SurveyService` falls
        // back to its cached list on error, so without this gate a transient
        // network failure could surface a survey that the server may have
        // already retired. Matches the policy in `StopViewModel.refreshSurveys`.
        guard surveyOrchestrator.lastError == nil else { return }

        // Eligibility can change while the refresh is in flight (a different
        // path completing or dismissing a survey, the reminder advancing).
        // Re-check before emitting.
        guard !hasShownSurveyThisSession, surveyOrchestrator.isEligible() else { return }
        guard let survey = surveyOrchestrator.findMapSurvey() else { return }

        // Flip the flag synchronously *before* `send`, so a second
        // `checkForSurveyPrompt()` racing through the post-await re-check
        // sees the flag set and bails out. `didPresentSurveyPrompt` rolls
        // it back if presentation didn't actually happen.
        hasShownSurveyThisSession = true
        surveyToPresentSubject.send(survey)
    }

    /// Reports back from the consumer after attempting to present. On
    /// `presented == true`, advances the reminder. On `presented == false`
    /// (presenter went away between emit and present), rolls back the
    /// session flag so a later check can re-emit.
    func didPresentSurveyPrompt(_ survey: Survey, presented: Bool) {
        if presented {
            surveyOrchestrator.noteReminderAndAdvanceSession()
        } else {
            hasShownSurveyThisSession = false
        }
    }

    // MARK: - LocationServiceDelegate

    nonisolated func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.locationAuthStatus = status
        }
    }

    nonisolated func locationService(_ service: LocationService, accuracyAuthorizationChanged accuracyAuthorization: CLAccuracyAuthorization) {
        Task { @MainActor in
            self.accuracyAuthorization = accuracyAuthorization
        }
    }
}
