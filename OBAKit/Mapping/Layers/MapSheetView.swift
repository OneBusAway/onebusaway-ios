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
    let group: MapLayerGroup

    /// Unavailable blocks turning a layer on; an enabled layer is always switchable off.
    var isTapEnabled: Bool { unavailableReason == nil || isEnabled }

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
@MainActor final class MapSheetModel: ObservableObject {

    private let mapRegionManager: MapRegionManager
    private let mapViewModel: MapViewModel

    /// Reads through to the view model so it can't drift while the sheet is open
    /// (the SwiftUI panel's map-type button can change it out from under us).
    var selectedBaseType: MapBaseType { mapViewModel.mapType }

    private var cancellables = Set<AnyCancellable>()

    init(mapRegionManager: MapRegionManager, mapViewModel: MapViewModel) {
        self.mapRegionManager = mapRegionManager
        self.mapViewModel = mapViewModel

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
            return MapLayerTile(id: layer.id, title: layer.title, iconName: layer.iconName, isEnabled: isEnabled(layer), unavailableReason: reason, group: layer.group)
        }
    }

    func toggle(_ tile: MapLayerTile) {
        guard let layer = mapRegionManager.mapLayer(id: tile.id) else { return }
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

    private static let sheetBackground = Color(uiColor: .systemGroupedBackground)
    private static let gridSpacing: CGFloat = 12

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    basemapPicker
                    layerGroup(title: Strings.mapLayersGroupTransit, group: .transit, tint: Color(uiColor: ThemeColors.shared.brandAccent))
                    if model.showsRentalsGroup {
                        layerGroup(title: Strings.mapLayersGroupRentals, group: .otherModes, tint: Color(uiColor: .rentalPurple))
                    }
                    if model.showsRangeChips {
                        RentalRangeChipRow(presets: model.rangeFilterPresets, selectedID: model.selectedRangePresetID) { model.selectRangePreset(id: $0) }
                    }
                    pointsOfInterestCard
                }
                .padding(16)
            }
            .background(Self.sheetBackground)
            .navigationTitle(OBALoc("map_sheet.title", value: "Map", comment: "Title of the Map sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if model.showsResetButton {
                        Button(OBALoc("map_sheet.reset", value: "Reset", comment: "Button restoring the default map layer configuration")) {
                            model.resetToDefaults()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Strings.done) { dismiss() }
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

    // MARK: - Points of Interest

    private var pointsOfInterestCard: some View {
        Toggle(isOn: Binding(get: { model.showsPointsOfInterest }, set: { model.setShowsPointsOfInterest($0) })) {
            Label(
                OBALoc("map_sheet.shows_points_of_interest", value: "Points of Interest", comment: "Map sheet toggle for Apple MapKit Points of Interest (restaurants, shops, etc.)"),
                systemImage: "mappin.and.ellipse"
            )
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
