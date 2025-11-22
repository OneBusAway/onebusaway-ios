//
//  SurveyAPIService.swift
//  OBAKitCore
//
//  Created by Mohamed Sliem on 22/11/2025.
//

import Foundation
import os.log

public actor SurveyAPIService: @preconcurrency APIService {
    
    public let configuration: APIServiceConfiguration
    
    public nonisolated let dataLoader: any URLDataLoader
    
    public let logger =  os.Logger(subsystem: "org.onebusaway.iphone", category: "SurveyAPIService")

    nonisolated let urlBuilder: RESTAPIURLBuilder
    nonisolated let decoder: JSONDecoder

    public init(_ configuration: APIServiceConfiguration, dataLoader: URLDataLoader = URLSession.shared) {
        self.configuration = configuration
        self.dataLoader = dataLoader
        
        /// sidecarURL will be passed as baseURL
        self.urlBuilder = RESTAPIURLBuilder(baseURL: configuration.baseURL, defaultQueryItems: configuration.defaultQueryItems)
        
        // contains logic of decoding the date format correctly in survey response
        self.decoder = JSONDecoder.obacoServiceDecoder
    }
    
    public func getSurveys() async throws -> 
}
