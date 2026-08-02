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
    @ObservedObject var model: MapSheetModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                basemapSection

                mapDisplaySection

                layerSection(
                    title: OBALoc("map_sheet.transit_group", value: "Transit", comment: "Map sheet group header for transit layers"),
                    group: .transit
                )

                otherModesSection
            }
            .navigationTitle(OBALoc("map_sheet.title", value: "Map", comment: "Title of the Map sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Shown only when current state differs from the defaults.
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

    // MARK: - Basemap Tiles

    private var basemapSection: some View {
        Section {
            HStack(spacing: 12) {
                basemapTile(
                    .standard,
                    title: OBALoc("map_sheet.basemap_standard", value: "Standard", comment: "Basemap style: standard street map"),
                    systemImage: "map"
                )
                basemapTile(
                    .satellite,
                    title: OBALoc("map_sheet.basemap_satellite", value: "Satellite", comment: "Basemap style: satellite imagery"),
                    systemImage: "globe.americas.fill"
                )
                basemapTile(
                    .hybrid,
                    title: OBALoc("map_sheet.basemap_hybrid", value: "Hybrid", comment: "Basemap style: satellite imagery with labels"),
                    systemImage: "map.fill"
                )
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private func basemapTile(_ type: MapBaseType, title: String, systemImage: String) -> some View {
        let isSelected = model.selectedBaseType == type

        return Button {
            model.selectBaseType(type)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                    )

                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Map Display

    /// MapKit chrome that isn't a stackable layer — currently just Points of
    /// Interest. Lives under the basemap tiles so it's always reachable, even
    /// in regions with no rental layers.
    private var mapDisplaySection: some View {
        Section(OBALoc("map_sheet.display_group", value: "Map display", comment: "Map sheet section for display options like Points of Interest")) {
            Toggle(isOn: Binding(
                get: { model.showsPointsOfInterest },
                set: { model.setShowsPointsOfInterest($0) }
            )) {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    Text(OBALoc(
                        "map_sheet.shows_points_of_interest",
                        value: "Points of Interest",
                        comment: "Map sheet toggle for Apple MapKit Points of Interest (restaurants, shops, etc.)"
                    ))
                }
            }
        }
    }

    // MARK: - Layer Rows

    @ViewBuilder
    private func layerSection(title: String, group: MapLayerGroup) -> some View {
        let layers = model.visibleLayers(in: group)
        if !layers.isEmpty {
            Section(title) {
                ForEach(layers, id: \.id) { layer in
                    layerRow(layer)
                }
            }
        }
    }

    /// The non-transit section, which carries the range-filter row beneath its
    /// layer toggles. The row shows whenever a rental layer row is visible — not
    /// only when one is enabled — so it doesn't jump in and out of the sheet as the
    /// rider toggles them, and so the filter can be set before turning a layer on.
    @ViewBuilder
    private var otherModesSection: some View {
        let layers = model.visibleLayers(in: .otherModes)
        if !layers.isEmpty {
            Section(OBALoc("map_sheet.other_modes_group", value: "Other ways to get around", comment: "Map sheet group header for non-transit mobility layers")) {
                ForEach(layers, id: \.id) { layer in
                    layerRow(layer)
                }
                rangeFilterRow
            }
        }
    }

    /// `.menu` is stated explicitly rather than left to `.automatic`, which Apple
    /// documents as "based on the picker's context" — in a List that has resolved
    /// to a navigation link in some OS versions and a menu in others.
    private var rangeFilterRow: some View {
        Picker(selection: Binding(
            get: { model.selectedRangePresetID },
            set: { model.selectRangePreset(id: $0) }
        )) {
            ForEach(model.rangeFilterPresets) { preset in
                Text(preset.title).tag(preset.meters)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bolt")
                    .foregroundStyle(Color(uiColor: .rentalPurple))
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(OBALoc("map_sheet.minimum_range", value: "Minimum range", comment: "Map sheet row label for the rental minimum-range filter"))
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private func layerRow(_ layer: MapLayer) -> some View {
        // Unavailable rows are dimmed with a reason instead of hidden or left
        // toggleable: an enabled layer that cannot load would read as "there is
        // nothing here," which is a lie.
        let unavailableReason: String? = {
            if case .unavailable(let reason) = layer.availability { return reason }
            return nil
        }()

        HStack(spacing: 12) {
            Image(systemName: layer.iconName)
                .foregroundStyle(Color(uiColor: layer.tintColor))
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(layer.title)
                if let unavailableReason {
                    Text(unavailableReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle(layer.title, isOn: Binding(
                get: { model.isEnabled(layer) },
                set: { model.setEnabled($0, layer: layer) }
            ))
            .labelsHidden()
            // Unavailable blocks turning a layer *on* (it can't load), but an
            // enabled layer must always be switchable off — a failing layer the
            // rider can't disable is a stuck switch.
            .disabled(unavailableReason != nil && !model.isEnabled(layer))
        }
        .opacity(unavailableReason == nil ? 1 : 0.5)
    }
}
