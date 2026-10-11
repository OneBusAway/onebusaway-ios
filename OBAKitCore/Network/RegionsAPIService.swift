//
//  RegionsAPIService.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import os.log

public class RegionsAPIService: APIService {
    public let configuration: APIServiceConfiguration
    public let dataLoader: URLDataLoader
    public let logger = os.Logger(subsystem: "org.onebusaway.iphone", category: "RegionsAPIService")

    private let urlBuilder: RESTAPIURLBuilder

    public required init(_ configuration: APIServiceConfiguration, dataLoader: URLDataLoader) {
        self.configuration = configuration
        self.dataLoader = dataLoader

        self.urlBuilder = RESTAPIURLBuilder(baseURL: configuration.baseURL, defaultQueryItems: configuration.defaultQueryItems)
    }

    public nonisolated func getRegions(apiPath: String) async throws -> RESTAPIResponse<[Region]> {
        return try await getData(
            for: urlBuilder.generateURL(path: apiPath),
            decodeRESTAPIResponseAs: [Region].self,
            using: JSONDecoder.RESTDecoder()
        )
    }
}

extension RegionsAPIService {
    /// Builds a regions-list service without a `CoreApplication`.
    ///
    /// The watch app's counterpart to `RESTAPIService.standalone`. It exists
    /// because `APIServiceConfiguration`'s initializers are internal, so no
    /// host outside this module can otherwise construct one. Mirrors
    /// `CoreApplication.regionsAPIService` (`regionIdentifier: nil`). The
    /// regions file path is a per-call argument of `getRegions(apiPath:)`, not
    /// part of the configuration.
    public static func standalone(
        baseURL: URL,
        apiKey: String,
        appVersion: String,
        uuid: String,
        dataLoader: URLDataLoader = URLSession.shared
    ) -> RegionsAPIService {
        RegionsAPIService(
            APIServiceConfiguration(
                baseURL: baseURL,
                apiKey: apiKey,
                uuid: uuid,
                appVersion: appVersion,
                regionIdentifier: nil
            ),
            dataLoader: dataLoader
        )
    }
}
