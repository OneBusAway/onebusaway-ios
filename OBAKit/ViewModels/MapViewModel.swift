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
/// Keeping this MapKit-free matches the `PanelDetent` pattern in `MapPanelViewModel`.
enum MapBaseType {
    case standard
    case hybrid
}

/// Shared ViewModel for the main map screen.
///
/// Consumed by `MapViewController` (UIKit, via Combine `sink`) and by
/// future `NewMapView` (SwiftUI, via `@StateObject`).
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

    /// The current weather forecast, if loaded.
    @Published private(set) var weather: WeatherForecast?

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

    func loadWeather() async {
        guard let apiService = application.obacoService else { return }
        do {
            weather = try await apiService.getWeather()
        } catch {
            weather = nil
            Logger.error("Failed to load weather: \(error.localizedDescription)")
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
    /// consumer presents it and reports back via `didPresentSurveyPrompt(_:)`
    /// so the reminder + session flag advance only on confirmed presentation.
    /// Matches the previous `MapViewController.checkForMapSurvey()` semantics.
    func checkForSurveyPrompt() async {
        guard !hasShownSurveyThisSession else { return }
        guard surveyOrchestrator.isEligible() else { return }

        await surveyOrchestrator.refreshSurveys()

        // Re-check after the await: a second `checkForSurveyPrompt()` can pass
        // the pre-await guard while this task is suspended, so without this
        // both tasks would emit and present a card twice.
        guard !hasShownSurveyThisSession else { return }
        guard let survey = application.surveyService.findSurveyForMap() else { return }

        surveyToPresentSubject.send(survey)
    }

    /// Reports back from the consumer after a successful presentation. Advances
    /// the reminder and flips the session flag. Idempotent within a session.
    func didPresentSurveyPrompt(_ survey: Survey) {
        guard !hasShownSurveyThisSession else { return }
        surveyOrchestrator.noteReminderAndAdvanceSession()
        hasShownSurveyThisSession = true
    }

    /// Re-enables the session prompt. Used by tests and any future
    /// region-change flow that wants the next map appearance to re-prompt.
    func resetSurveySession() {
        hasShownSurveyThisSession = false
    }

    // MARK: - LocationServiceDelegate

    nonisolated func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.locationAuthStatus = status
        }
    }
}
