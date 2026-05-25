//
//  NearbyStopsViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import OBAKitCore

@MainActor
final class NearbyStopsViewModel: ObservableObject {

    @Published private(set) var stops: [Stop] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var operationError: Error?

    private let coordinate: CLLocationCoordinate2D
    private let apiService: RESTAPIService?

    init(coordinate: CLLocationCoordinate2D, application: Application) {
        self.coordinate = coordinate
        self.apiService = application.apiService
    }

    init(coordinate: CLLocationCoordinate2D, apiService: RESTAPIService?) {
        self.coordinate = coordinate
        self.apiService = apiService
    }

    func loadStops() async {
        guard !isLoading, let apiService else { return }

        isLoading = true
        operationError = nil

        defer { isLoading = false }

        do {
            stops = try await apiService.getStops(coordinate: coordinate).list
        } catch {
            operationError = error
        }
    }
}
