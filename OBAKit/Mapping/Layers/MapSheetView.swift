//
//  MapSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import OBAKitCore
import SwiftUI
import UIKit

/// One tile of the layers grid (spec 3.9).
struct MapLayerTile: Identifiable, Equatable {
    let id: String
    let title: String
    let iconName: String
    let isEnabled: Bool
    let unavailableReason: String?
    let isTapEnabled: Bool

    init(
        id: String,
        title: String,
        iconName: String,
        isEnabled: Bool,
        unavailableReason: String?,
        isTapEnabled: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.isEnabled = isEnabled
        self.unavailableReason = unavailableReason
        self.isTapEnabled = isTapEnabled ?? (unavailableReason == nil || isEnabled)
    }

    var subtitle: String {
        if let unavailableReason { return unavailableReason }
        return isEnabled ? Strings.mapLayersStateOn : Strings.mapLayersStateOff
    }
}

/// The Map sheet: basemap styles on top, stackable layer toggles below.
///
/// Presented from the basemap button in the map's control stack — a browse layer
/// buried in Settings is a discoverability failure, so this sheet is the single
/// canonical place riders turn layers on and off. Settings may mirror the same
/// UserDefaults keys, but it does not own them.
@MainActor final class MapSheetModel: NSObject, ObservableObject, MapRegionDelegate {

    private let mapRegionManager: MapRegionManager
    private let mapViewModel: MapViewModel

    /// Reads through to the view model so it can't drift while the sheet is open
    /// (the SwiftUI panel's map-type button can change it out from under us).
    var selectedBaseType: MapBaseType { mapViewModel.mapType }

    /// Each map root shows the route through its own route-display path; the
    /// sheet only says which route was picked. Required so a host can't build a
    /// Routes on Map list whose rows silently do nothing.
    private let onSelectRoute: (Route) -> Void

    private var cancellables = Set<AnyCancellable>()

    /// Where the Trip Suggestions switch is stored, when this map offers suggestions.
    /// Only the panel does, so the classic map leaves it `nil` and the row is hidden.
    private let tripSuggestionDefaults: UserDefaults?

    init(
        mapRegionManager: MapRegionManager,
        mapViewModel: MapViewModel,
        tripSuggestionDefaults: UserDefaults? = nil,
        onSelectRoute: @escaping (Route) -> Void
    ) {
        self.mapRegionManager = mapRegionManager
        self.mapViewModel = mapViewModel
        self.tripSuggestionDefaults = tripSuggestionDefaults
        self.onSelectRoute = onSelectRoute
        super.init()

        // Stops load after the camera settles, so the zoom flip below fires
        // before the Routes on Map list has anything new to show. Weakly held.
        mapRegionManager.addDelegate(self)

        // Zooming past the stop-loading threshold behind the sheet must flip an
        // open Routes on Map list to its zoomed-out state.
        mapViewModel.$showZoomWarning
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .mapLayerAvailabilityDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Settings may mirror this same UserDefaults key while the sheet stays its
        // owner, so an external writer must not leave an open sheet showing a stale
        // rung.
        NotificationCenter.default.publisher(for: .rentalRangeFilterDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .mapPointsOfInterestVisibilityDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Basemap

    func selectBaseType(_ type: MapBaseType) {
        objectWillChange.send()
        mapViewModel.setMapType(type)
    }

    // MARK: - Layers

    /// Layers to show for a group. Unsupported layers are hidden entirely —
    /// a row for something that can never load isn't a feature, it's a bug report.
    func visibleLayers(in group: MapLayerGroup) -> [MapLayer] {
        mapRegionManager.mapLayers.filter { $0.group == group && $0.availability != .unsupported }
    }

    func isEnabled(_ layer: MapLayer) -> Bool {
        mapRegionManager.isMapLayerEnabled(id: layer.id)
    }

    func setEnabled(_ enabled: Bool, layer: MapLayer) {
        objectWillChange.send()
        mapRegionManager.setMapLayerEnabled(enabled, id: layer.id)
    }

    func tiles(in group: MapLayerGroup) -> [MapLayerTile] {
        visibleLayers(in: group).map { layer in
            let reason: String? = {
                if case .unavailable(let reason) = layer.availability { return reason }
                return nil
            }()
            return MapLayerTile(
                id: layer.id,
                title: layer.title,
                iconName: layer.iconName,
                isEnabled: isEnabled(layer),
                unavailableReason: reason,
                isTapEnabled: mapRegionManager.canToggleMapLayer(id: layer.id)
            )
        }
    }

    func toggle(_ tile: MapLayerTile) {
        guard mapRegionManager.canToggleMapLayer(id: tile.id),
              let layer = mapRegionManager.mapLayer(id: tile.id) else { return }
        setEnabled(!tile.isEnabled, layer: layer)
    }

    /// The group, header included, disappears when no rental layer is registered.
    var showsRentalsGroup: Bool { !visibleLayers(in: .otherModes).isEmpty }

    /// Chips show whenever the group does, so the range can be set before a layer is on.
    var showsRangeChips: Bool { showsRentalsGroup }

    var showsResetButton: Bool {
        mapRegionManager.mapLayersDifferFromDefaults
    }

    func resetToDefaults() {
        objectWillChange.send()
        mapRegionManager.resetMapLayersToDefaults()
    }

    // MARK: - Rental Range Filter

    /// Computed once per sheet presentation: the ladder involves a
    /// MeasurementFormatter and a localized string, neither worth redoing per render.
    let rangeFilterPresets = RentalRangePreset.presets()

    /// The rung to highlight. A stored value that isn't on the current ladder — the
    /// rider's locale changed since they chose it — highlights the closest rung
    /// without the stored preference being rewritten.
    var selectedRangePresetID: Int {
        RentalRangePreset.nearest(
            toMeters: mapRegionManager.rentalRangeFilter.minimumRangeMeters,
            in: rangeFilterPresets
        )?.id ?? 0
    }

    func selectRangePreset(id: Int) {
        objectWillChange.send()
        mapRegionManager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: id)
    }

    // MARK: - Points of Interest

    var showsPointsOfInterest: Bool {
        mapRegionManager.mapViewShowsPointsOfInterest
    }

    func setShowsPointsOfInterest(_ shows: Bool) {
        objectWillChange.send()
        mapRegionManager.mapViewShowsPointsOfInterest = shows
    }

    // MARK: - Trip Suggestions

    var showsTripSuggestionsSetting: Bool { tripSuggestionDefaults != nil }

    var tripSuggestionsEnabled: Bool {
        guard let tripSuggestionDefaults else { return false }
        return TripSuggestionSettings.isEnabled(userDefaults: tripSuggestionDefaults)
    }

    func setTripSuggestionsEnabled(_ enabled: Bool) {
        guard let tripSuggestionDefaults else { return }
        objectWillChange.send()
        TripSuggestionSettings.setEnabled(enabled, userDefaults: tripSuggestionDefaults)
    }

    // MARK: - Routes on Map

    /// `showZoomWarning` rather than `mapRegionManager.zoomInStatus`: the panel
    /// root never moves the manager's offscreen `mapView`, while both roots keep
    /// the view model's flag in step with their camera.
    var routeFilterContent: RouteFilterOptions.Content {
        RouteFilterOptions.content(stops: mapRegionManager.stops, isZoomedOut: mapViewModel.showZoomWarning)
    }

    func selectRoute(_ route: Route) {
        onSelectRoute(route)
    }

    func mapRegionManager(_ manager: MapRegionManager, stopsUpdated stops: [Stop]) {
        objectWillChange.send()
    }
}

struct MapSheetView: View {

    /// `@StateObject`, not `@ObservedObject`: the panel builds this view inside
    /// `MapPanelRootView.body`, so an eager model would be rebuilt — with its
    /// three subscriptions — on every re-render. The autoclosure runs once per
    /// view identity. The UIKit host's eager `MapSheetModel(...)` wraps unchanged.
    @StateObject private var model: MapSheetModel

    @Environment(\.dismiss) private var dismiss

    init(model: @autoclosure @escaping () -> MapSheetModel) {
        _model = StateObject(wrappedValue: model())
    }

    private static let gridSpacing: CGFloat = 12

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    basemapPicker
                    routesOnMapCard
                    layerGroup(title: Strings.mapLayersGroupTransit, group: .transit, tint: Color(uiColor: ThemeColors.shared.brandAccent))
                    if model.showsRentalsGroup {
                        layerGroup(title: Strings.mapLayersGroupRentals, group: .otherModes, tint: Color(uiColor: .rentalPurple))
                    }
                    if model.showsRangeChips {
                        RentalRangeChipRow(presets: model.rangeFilterPresets, selectedID: model.selectedRangePresetID) { model.selectRangePreset(id: $0) }
                    }
                    if model.showsTripSuggestionsSetting {
                        tripSuggestionsCard
                    }
                    pointsOfInterestCard
                }
                .padding(16)
            }
            .mapSheetBackground()
            .navigationTitle(OBALoc("map_sheet.title", value: "Map", comment: "Title of the Map sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if model.showsResetButton {
                        Button {
                            model.resetToDefaults()
                        } label: {
                            // The icon lets the item join a vertical bar (iPhone Duo).
                            Label(OBALoc("map_sheet.reset", value: "Reset", comment: "Button restoring the default map layer configuration"), systemImage: "arrow.counterclockwise")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SheetDismissButton(.done) { dismiss() }
                }
            }
        }
    }

    // MARK: - Basemap

    /// Text-only segments: the segmented style drops a `Label`'s icon.
    private var basemapPicker: some View {
        Picker(selection: Binding(get: { model.selectedBaseType }, set: { model.selectBaseType($0) })) {
            Text(OBALoc("map_sheet.basemap_standard", value: "Standard", comment: "Basemap style: standard street map")).tag(MapBaseType.standard)
            Text(OBALoc("map_sheet.basemap_satellite", value: "Satellite", comment: "Basemap style: satellite imagery")).tag(MapBaseType.satellite)
            Text(OBALoc("map_sheet.basemap_hybrid", value: "Hybrid", comment: "Basemap style: satellite imagery with labels")).tag(MapBaseType.hybrid)
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Routes on Map

    /// Directly under the basemap picker, ahead of the layer tiles, because it is
    /// the one row here that changes *which* transit the map shows. The caption
    /// carries the way back out, since the filter is cleared from the route
    /// sheet's Close button rather than from here.
    private var routesOnMapCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink {
                RoutesOnMapView(model: model)
                    .mapSheetBackground()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    Text(Strings.routesOnMapTitle)
                        .foregroundStyle(.primary)
                    Spacer()
                    if case .routes(let routes) = model.routeFilterContent {
                        Text(routes.count, format: .number)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .mapSheetCard()
            }
            .buttonStyle(.plain)
            Text(Strings.routesOnMapFooter)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Layer groups

    @ViewBuilder
    private func layerGroup(title: String, group: MapLayerGroup, tint: Color) -> some View {
        let tiles = model.tiles(in: group)
        if !tiles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Self.gridSpacing), GridItem(.flexible(), spacing: Self.gridSpacing)], spacing: Self.gridSpacing) {
                    ForEach(tiles) { tile in
                        MapLayerTileView(tile: tile, tint: tint) { model.toggle(tile) }
                    }
                }
            }
        }
    }

    // MARK: - Trip Suggestions

    /// Under the transit layers because it's about riding transit, with a footer
    /// saying what it does, as the Routes on Map card has.
    private var tripSuggestionsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { model.tripSuggestionsEnabled }, set: { model.setTripSuggestionsEnabled($0) })) {
                Label(
                    OBALoc("map_sheet.trip_suggestions", value: "Trip Suggestions", comment: "Map sheet switch that lets the app offer to track the trip the rider seems to be riding."),
                    systemImage: "bus"
                )
            }
            .mapSheetCard()
            Text(OBALoc(
                "map_sheet.trip_suggestions_footer",
                value: "Offer to track your trip when you’re riding a bus. Requires Precise Location.",
                comment: "Footer under the Trip Suggestions switch in the Map sheet."
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Points of Interest

    private var pointsOfInterestCard: some View {
        Toggle(isOn: Binding(get: { model.showsPointsOfInterest }, set: { model.setShowsPointsOfInterest($0) })) {
            Label(
                OBALoc("map_sheet.shows_points_of_interest", value: "Points of Interest", comment: "Map sheet toggle for Apple MapKit Points of Interest (restaurants, shops, etc.)"),
                systemImage: "mappin.and.ellipse"
            )
        }
        .mapSheetCard()
    }
}

private extension View {
    /// Every screen in the sheet's stack wears this, root and pushed alike: left
    /// to the sheet's Liquid Glass, a pushed screen washes out to mid-grey over a
    /// dark map, too light for white text.
    func mapSheetBackground() -> some View {
        containerBackground(Color(uiColor: .systemGroupedBackground), for: .navigation)
    }

    /// The sheet's full-width cards share the layer tiles' fill and corners, so
    /// they stand out from the grouped background in dark mode too.
    func mapSheetCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: MapLayerTileView.cornerRadius, style: .continuous)
        return padding(16)
            .background(MapLayerTileView.offBackground, in: shape)
            .contentShape(shape)
    }
}
