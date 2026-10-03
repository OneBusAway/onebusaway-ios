//
//  RESTAPIService.swift
//  OBAKitCore
//
//  Created by Alan Chu on 12/28/22.
//

import Foundation
import os.log

/// Makes API calls to the OBA REST service and converts the server's responses into model objects.
public actor RESTAPIService: @preconcurrency APIService {
    public let configuration: APIServiceConfiguration
    public nonisolated let dataLoader: URLDataLoader

    /// The configuration's base URL, readable without an actor hop. `OnDemandSupport`
    /// keys on it, and `@MainActor` callers consult support synchronously.
    public nonisolated let baseURL: URL

    /// Where the `services-for-location` probe records a server that lacks
    /// `/api/ondemand`. Injectable so tests never share the process-wide cache.
    public nonisolated let onDemandSupport: OnDemandSupport

    public let logger = os.Logger(subsystem: "org.onebusaway.iphone", category: "RESTAPIService")

    nonisolated let urlBuilder: RESTAPIURLBuilder
    nonisolated let decoder: JSONDecoder

    public init(
        _ configuration: APIServiceConfiguration,
        dataLoader: URLDataLoader = URLSession.shared,
        onDemandSupport: OnDemandSupport = .shared
    ) {
        self.configuration = configuration
        self.dataLoader = dataLoader
        self.baseURL = configuration.baseURL
        self.onDemandSupport = onDemandSupport
        self.urlBuilder = RESTAPIURLBuilder(
            baseURL: configuration.baseURL,
            defaultQueryItems: configuration.defaultQueryItems,
            surveyBaseURL: configuration.surveyBaseURL
        )
        self.decoder = JSONDecoder.RESTDecoder(regionIdentifier: configuration.regionIdentifier)
    }

    /// Satisfies `APIService`'s two-parameter `init(_:dataLoader:)` requirement.
    /// A default argument value doesn't count toward protocol witness matching,
    /// so the three-parameter initializer above can't stand in for it on its own.
    public init(_ configuration: APIServiceConfiguration, dataLoader: URLDataLoader) {
        self.init(configuration, dataLoader: dataLoader, onDemandSupport: .shared)
    }
}
