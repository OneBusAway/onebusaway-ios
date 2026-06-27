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
    /// Persistence is handled by the consuming layer (UIKit: `MapViewController`'s `$mapType` sink).
    @Published private(set) var mapType: MapBaseType

    /// The current location authorization status. Used by the UI to show/hide location controls.
    @Published private(set) var locationAuthStatus: CLAuthorizationStatus

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

    // MARK: - Init

    init(application: Application, initialMapType: MapBaseType = .standard) {
        self.application = application
        self.mapType = initialMapType
        self.locationAuthStatus = application.locationService.authorizationStatus
        self.surveyOrchestrator = SurveyOrchestrator(surveyService: application.surveyService)
        super.init()
        application.locationService.addDelegate(self)
    }

    deinit {
        application.locationService.removeDelegate(self)
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

    // MARK: - Map Type

    /// Toggles between the standard and hybrid base map types.
    /// The consuming layer (UIKit: `MapViewController`'s `$mapType` sink) persists the selection.
    func toggleMapType() {
        mapType = mapType == .standard ? .hybrid : .standard
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
}
