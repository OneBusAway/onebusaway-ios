//
//  OnDemandProbeController+Application.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import OBAKitCore

extension OnDemandProbeController {

    /// The controller both shells build: wired to the app's REST service,
    /// location service (triggers 2 and 5) and regions service (deployment).
    static func make(application: Application) -> OnDemandProbeController {
        let cache = OnDemandGeometryCache { apiService, serviceID in
            try await apiService.getOnDemandService(id: serviceID, geometryDetail: .full).entry.areas
        }
        let controller = OnDemandProbeController(
            apiService: { [weak application] in application?.apiService },
            geometryCache: cache,
            isLocationAuthorized: { [weak application] in application?.locationService.isLocationUseAuthorized ?? false },
            currentLocation: { [weak application] in application?.locationService.currentLocation }
        )
        application.locationService.addDelegate(controller)
        application.regionsService.addDelegate(controller)
        return controller
    }
}

// MARK: - RegionsServiceDelegate

extension OnDemandProbeController: RegionsServiceDelegate {
    func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        deploymentDidChange()
    }
}
