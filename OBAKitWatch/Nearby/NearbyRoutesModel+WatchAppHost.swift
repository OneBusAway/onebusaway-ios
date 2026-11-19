//
//  NearbyRoutesModel+WatchAppHost.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import OBAKitCore

extension NearbyRoutesModel {
    public convenience init(
        host: WatchAppHost,
        cadencePolicy: NearbyPollingCadencePolicy = .standard,
        powerStateProvider: @escaping PowerStateProvider = { ProcessInfo.processInfo.isLowPowerModeEnabled }
    ) {
        self.init(
            authorizationProvider: { [weak host] in host?.authorizationStatus ?? .notDetermined },
            requestAuthorization: { [weak host] in host?.locationService.requestInUseAuthorization() },
            locationRequester: { [weak host] in
                guard let host else { throw LocationServiceError.notAuthorized }
                return try await host.locationService.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)
            },
            hasRegion: { [weak host] in host?.regionsService.physicallyLocatedRegion != nil },
            apiServiceProvider: { [weak host] in host?.apiService },
            cadencePolicy: cadencePolicy,
            powerStateProvider: powerStateProvider
        )
    }
}
