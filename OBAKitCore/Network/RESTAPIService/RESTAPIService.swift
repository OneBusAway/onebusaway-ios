//
//  RESTAPIService.swift
//  OBAKitCore
//
//  Created by Alan Chu on 12/28/22.
//

import Foundation
import os.log

public actor RESTAPIService: APIService {
    public let configuration: APIServiceConfiguration
    public nonisolated let dataLoader: URLDataLoader

    let logger = os.Logger(subsystem: "org.onebusaway.iphone", category: "RESTAPIService")

    nonisolated let urlBuilder: RESTAPIURLBuilder
    nonisolated let decoder: JSONDecoder

    public init(_ configuration: APIServiceConfiguration, dataLoader: URLDataLoader = URLSession.shared) {
        self.configuration = configuration
        self.dataLoader = dataLoader
        self.urlBuilder = RESTAPIURLBuilder(baseURL: configuration.baseURL, defaultQueryItems: configuration.defaultQueryItems)
        self.decoder = JSONDecoder.RESTDecoder(regionIdentifier: configuration.regionIdentifier)
    }
}
