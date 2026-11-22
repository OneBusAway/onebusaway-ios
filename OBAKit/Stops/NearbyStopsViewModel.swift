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
    private let regionName: () -> String?
    private let isCellularDataRestricted: () -> Bool

    convenience init(coordinate: CLLocationCoordinate2D, application: Application) {
        self.init(
            coordinate: coordinate,
            apiService: application.apiService,
            regionName: { [weak application] in application?.currentRegionName },
            isCellularDataRestricted: { [weak application] in application?.isCellularDataRestricted ?? false }
        )
    }

    init(
        coordinate: CLLocationCoordinate2D,
        apiService: RESTAPIService?,
        regionName: @escaping () -> String? = { nil },
        isCellularDataRestricted: @escaping () -> Bool = { false }
    ) {
        self.coordinate = coordinate
        self.apiService = apiService
        self.regionName = regionName
        self.isCellularDataRestricted = isCellularDataRestricted
    }

    /// `operationError` as the rider should read it — classified the same way as
    /// `StopViewModel.operationErrorMessage`, so a raw `URLError` or decoding failure
    /// reads as an explanation rather than a code.
    var operationErrorMessage: String? {
        guard let operationError else { return nil }
        return ErrorClassifier.classify(
            operationError,
            regionName: regionName(),
            isCellularDataRestricted: isCellularDataRestricted()
        ).localizedDescription
    }

    func loadStops() async {
        guard !isLoading else { return }
        guard let apiService else {
            // Misconfiguration (no API service available, e.g. region not selected). Surface
            // it through the same error channel as a load failure so the screen doesn't
            // sit silently empty with no signal to the user or in the logs.
            operationError = UnstructuredError(OBALoc(
                "nearby_stops_controller.no_api_service_error",
                value: "No transit data service is available. Please choose a region in Settings.",
                comment: "Error shown on the Nearby Stops screen when no API service is configured (e.g. no region selected)."
            ))
            return
        }

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
