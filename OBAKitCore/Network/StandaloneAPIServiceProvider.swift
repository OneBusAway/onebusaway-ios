//
//  StandaloneAPIServiceProvider.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Keeps a standalone `RESTAPIService` pointed at `RegionsService.currentRegion`
/// for hosts that build no `CoreApplication` (the watch app).
///
/// It is the region-to-service rule of `CoreApplication.refreshRESTAPIService`
/// with the survey and Obaco branches removed. Seeded from `currentRegion` at
/// init, because the `currentRegion` setter returns early on an unchanged
/// identifier and so delivers no `updatedRegion` on a warm launch. Rebuilt on
/// `updatedRegion` and on `updatedRegionsList` (a server-side edit to the
/// current region arrives only as a list update); nil when there is no region.
///
/// `RegionsService` holds its delegates weakly. The owner retains this object.
@MainActor
public final class StandaloneAPIServiceProvider: NSObject, RegionsServiceDelegate {
    public private(set) var apiService: RESTAPIService?

    private let apiKey: String
    private let appVersion: String
    private let uuid: String
    private let dataLoader: URLDataLoader

    public init(
        regionsService: RegionsService,
        apiKey: String,
        appVersion: String,
        uuid: String,
        dataLoader: URLDataLoader = URLSession.shared
    ) {
        self.apiKey = apiKey
        self.appVersion = appVersion
        self.uuid = uuid
        self.dataLoader = dataLoader
        super.init()

        rebuild(for: regionsService.currentRegion)
        regionsService.addDelegate(self)
    }

    private func rebuild(for region: Region?) {
        if let region {
            apiService = RESTAPIService.standalone(
                region: region,
                apiKey: apiKey,
                appVersion: appVersion,
                uuid: uuid,
                dataLoader: dataLoader
            )
        } else {
            apiService = nil
        }
    }

    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        rebuild(for: region)
    }

    public func regionsService(_ service: RegionsService, updatedRegionsList regions: [Region]) {
        rebuild(for: service.currentRegion)
    }
}
