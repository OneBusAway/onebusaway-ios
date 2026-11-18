//
//  MapLayerVisibilityState.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import UIKit
import OBAKitCore

/// A pure descriptor representing a registered map layer for selection decisions.
struct MapLayerDescriptor: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let iconName: String
    let group: MapLayerGroup
    let isEnabledByDefault: Bool
    var availability: MapLayerAvailability

    init(
        id: String,
        title: String = "",
        iconName: String = "",
        group: MapLayerGroup = .transit,
        isEnabledByDefault: Bool = true,
        availability: MapLayerAvailability = .available
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.group = group
        self.isEnabledByDefault = isEnabledByDefault
        self.availability = availability
    }

    @MainActor
    init(layer: MapLayer) {
        self.init(
            id: layer.id,
            title: layer.title,
            iconName: layer.iconName,
            group: layer.group,
            isEnabledByDefault: layer.isEnabledByDefault,
            availability: layer.availability
        )
    }
}

/// Pure, side-effect-free state managing map layer visibility, enablement, and availability.
///
/// Decouples layer selection decisions (defaults, persisted state, availability gating,
/// repeated toggling, and reset) from MapKit and rendering side effects. One pure state
/// drives the map toolbar badge, sheet controls, and layer pipeline.
struct MapLayerVisibilityState: Equatable, Sendable {
    private(set) var layers: [String: MapLayerDescriptor]
    private(set) var layerOrder: [String]
    private(set) var enabledLayerIDs: Set<String>
    var showsPointsOfInterest: Bool
    var rentalRangeFilter: RentalRangeFilter

    init(
        layers: [MapLayerDescriptor] = [],
        persistedEnabledIDs: Set<String>? = nil,
        showsPointsOfInterest: Bool = true,
        rentalRangeFilter: RentalRangeFilter = .any
    ) {
        var dict: [String: MapLayerDescriptor] = [:]
        var order: [String] = []
        var defaultEnabled = Set<String>()

        for layer in layers {
            dict[layer.id] = layer
            order.append(layer.id)
            if layer.isEnabledByDefault {
                defaultEnabled.insert(layer.id)
            }
        }

        self.layers = dict
        self.layerOrder = order
        self.enabledLayerIDs = persistedEnabledIDs ?? defaultEnabled
        self.showsPointsOfInterest = showsPointsOfInterest
        self.rentalRangeFilter = rentalRangeFilter
    }

    /// Whether a layer is marked as enabled.
    func isEnabled(id: String) -> Bool {
        enabledLayerIDs.contains(id)
    }

    /// Whether a layer is actively visible and eligible to draw.
    /// Unsupported layers are never visible even if their stored preference was on.
    func isLayerVisible(id: String) -> Bool {
        guard let layer = layers[id], layer.availability != .unsupported else { return false }
        return isEnabled(id: id)
    }

    /// Whether a layer tile or toggle can be tapped by the rider.
    /// Unavailable layers cannot be turned on, but an already-enabled layer can always be turned off.
    func canToggle(id: String) -> Bool {
        guard let layer = layers[id], layer.availability != .unsupported else { return false }
        if case .unavailable = layer.availability {
            return isEnabled(id: id)
        }
        return true
    }

    /// Pure toggle for a layer.
    /// Returns true if the state changed, or false if the toggle was a no-op or blocked by availability.
    @discardableResult
    mutating func toggle(id: String) -> Bool {
        guard canToggle(id: id) else { return false }
        if isEnabled(id: id) {
            enabledLayerIDs.remove(id)
        } else {
            enabledLayerIDs.insert(id)
        }
        return true
    }

    /// Sets enablement explicitly for a layer.
    /// Turning on an unavailable or unsupported layer is rejected.
    @discardableResult
    mutating func setEnabled(_ enabled: Bool, id: String) -> Bool {
        guard let layer = layers[id], layer.availability != .unsupported else { return false }
        if enabled {
            if case .unavailable = layer.availability { return false }
            return enabledLayerIDs.insert(id).inserted
        } else {
            return enabledLayerIDs.remove(id) != nil
        }
    }

    /// The number of enabled, non-unsupported layers.
    /// Pure state driving the badge on the map-type toolbar button.
    var enabledLayerCount: Int {
        layerOrder.filter { id in
            guard let layer = layers[id] else { return false }
            return layer.availability != .unsupported && isEnabled(id: id)
        }.count
    }

    /// Whether any layer, points of interest, or range filter differs from defaults.
    /// Drives the Map sheet's Reset affordance.
    var differsFromDefaults: Bool {
        if !showsPointsOfInterest { return true }
        if rentalRangeFilter != .any, layers.values.contains(where: { $0.group == .otherModes }) { return true }
        return layerOrder.contains { id in
            guard let layer = layers[id] else { return false }
            return isEnabled(id: id) != layer.isEnabledByDefault
        }
    }

    /// Restores every registered layer to its default enablement, clears the range filter,
    /// and turns points of interest back on.
    mutating func resetToDefaults() {
        var next = Set<String>()
        for id in layerOrder {
            if let layer = layers[id], layer.isEnabledByDefault {
                next.insert(id)
            }
        }
        enabledLayerIDs = next
        showsPointsOfInterest = true
        rentalRangeFilter = .any
    }

    /// Updates availability status for a layer without side effects.
    mutating func updateAvailability(_ availability: MapLayerAvailability, id: String) {
        guard var layer = layers[id] else { return }
        layer.availability = availability
        layers[id] = layer
    }

    /// Registers a layer descriptor with pure visibility state.
    mutating func register(layer: MapLayerDescriptor, persistedEnabled: Bool? = nil) {
        if layers[layer.id] == nil {
            layerOrder.append(layer.id)
        }
        layers[layer.id] = layer
        if let persisted = persistedEnabled {
            if persisted {
                enabledLayerIDs.insert(layer.id)
            } else {
                enabledLayerIDs.remove(layer.id)
            }
        } else if !enabledLayerIDs.contains(layer.id) && layer.isEnabledByDefault {
            enabledLayerIDs.insert(layer.id)
        }
    }

    /// Removes a layer from active registration.
    mutating func remove(id: String) {
        layers.removeValue(forKey: id)
        layerOrder.removeAll { $0 == id }
    }
}
