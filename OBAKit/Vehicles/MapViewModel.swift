//
//  VehiclesViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Combine
import MapKit
import SwiftUI
import OBAKitCore

/// View model that manages the MapView state and other general information.
@MainActor
class MapViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var isLoading: Bool = false
    @Published var error: Error?
    @Published var lastUpdated: Date?
    @Published var cameraPosition: MapCameraPosition = .automatic

    // MARK: - Internal Properties

    let application: Application

    // MARK: - Initialization

    init(application: Application) {
        self.application = application
    }

    // MARK: - Public Methods

    /// Centers the map on the user's current location
    func centerOnUserLocation() {
        cameraPosition = .userLocation(fallback: .automatic)
    }
}
