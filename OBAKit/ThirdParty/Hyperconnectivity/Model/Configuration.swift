//
//  Configuration.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 07/05/2020.
//

import Foundation

public struct HyperconnectivityConfiguration {
    public static let defaultConnectivityURLs = [
        URL(string: "https://www.apple.com/library/test/success.html"),
        URL(string: "https://captive.apple.com/hotspot-detect.html")
    ].compactMap { $0 }
    
    public static let defaultURLSessionConfiguration: URLSessionConfiguration = {
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.requestCachePolicy = .reloadIgnoringCacheData
        sessionConfiguration.urlCache = nil
        sessionConfiguration.timeoutIntervalForRequest = 5.0
        sessionConfiguration.timeoutIntervalForResource = 5.0
        return sessionConfiguration
    }()
    
    let callbackQueue: DispatchQueue
    let connectivityQueue: DispatchQueue
    let connectivityURLRequests: [URLRequest]
    let responseValidator: ResponseValidator
    let shouldCheckConnectivity: Bool
    
    /// % successful connections required to be deemed to have connectivity
    let successThreshold: Percentage
    let urlSessionConfiguration: URLSessionConfiguration
    
    public init(
        callbackQueue: DispatchQueue = DispatchQueue.main,
        connectivityQueue: DispatchQueue = DispatchQueue.global(qos: .utility),
        connectivityURLs: [URL] = Self.defaultConnectivityURLs,
        responseValidator: ResponseValidator? = nil,
        shouldCheckConnectivity: Bool = true,
        successThreshold: Percentage = Percentage(50.0),
        urlSessionConfiguration: URLSessionConfiguration = Self.defaultURLSessionConfiguration
    ) {
        self.init(
            callbackQueue: callbackQueue,
            connectivityQueue: connectivityQueue,
            connectivityURLRequests: connectivityURLs.map { URLRequest(url: $0) },
            responseValidator: responseValidator,
            shouldCheckConnectivity: shouldCheckConnectivity,
            successThreshold: successThreshold,
            urlSessionConfiguration: urlSessionConfiguration
        )
    }
    
    public init(
        callbackQueue: DispatchQueue = DispatchQueue.main,
        connectivityQueue: DispatchQueue = DispatchQueue.global(qos: .utility),
        connectivityURLRequests: [URLRequest],
        responseValidator: ResponseValidator? = nil,
        shouldCheckConnectivity: Bool = true,
        successThreshold: Percentage = Percentage(50.0),
        urlSessionConfiguration: URLSessionConfiguration = Self.defaultURLSessionConfiguration
    ) {
        let defaultValidator = ResponseStringValidator(
            validationMode: .containsExpectedResponseString
        )
        self.callbackQueue = callbackQueue
        self.connectivityQueue = connectivityQueue
        self.connectivityURLRequests = connectivityURLRequests
        self.responseValidator = responseValidator ?? defaultValidator
        self.shouldCheckConnectivity = shouldCheckConnectivity
        self.successThreshold = successThreshold
        self.urlSessionConfiguration = urlSessionConfiguration
    }
    
    func cloneForReachability() -> Self {
        return HyperconnectivityConfiguration(
            callbackQueue: callbackQueue,
            connectivityQueue: connectivityQueue,
            connectivityURLs: [],
            responseValidator: responseValidator,
            shouldCheckConnectivity: false,
            successThreshold: Percentage(0.0),
            urlSessionConfiguration: urlSessionConfiguration)
    }
    
    /// Convenience method for determining whether or not the response is valid.
    func isResponseValid(_ response: (Data, URLResponse)) -> Bool {
        responseValidator.isResponseValid(response.1, data: response.0)
    }
}
