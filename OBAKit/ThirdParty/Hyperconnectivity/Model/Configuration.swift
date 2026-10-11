//
//  Configuration.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 07/05/2020.
//

import Foundation

// OBA: `callbackQueue` (never read upstream), `connectivityQueue` (replaced by
// `Hyperconnectivity`'s own serial queue) and `shouldCheckConnectivity` (used only
// by the reachability publisher, which was not vendored) are gone.
nonisolated struct HyperconnectivityConfiguration {
    static let defaultConnectivityURLs = [
        URL(string: "https://www.apple.com/library/test/success.html"),
        URL(string: "https://captive.apple.com/hotspot-detect.html")
    ].compactMap { $0 }

    // OBA: computed rather than a shared `static let`, because
    // `URLSessionConfiguration` is mutable and not `Sendable`.
    static var defaultURLSessionConfiguration: URLSessionConfiguration {
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = 5.0
        sessionConfiguration.timeoutIntervalForResource = 5.0
        return sessionConfiguration
    }

    let connectivityURLRequests: [URLRequest]
    let responseValidator: any ResponseValidator

    /// % successful connections required to be deemed to have connectivity
    let successThreshold: Percentage
    let urlSessionConfiguration: URLSessionConfiguration

    init(
        connectivityURLs: [URL] = Self.defaultConnectivityURLs,
        responseValidator: (any ResponseValidator)? = nil,
        successThreshold: Percentage = Percentage(50.0),
        urlSessionConfiguration: URLSessionConfiguration = Self.defaultURLSessionConfiguration
    ) {
        self.init(
            connectivityURLRequests: connectivityURLs.map { URLRequest(url: $0) },
            responseValidator: responseValidator,
            successThreshold: successThreshold,
            urlSessionConfiguration: urlSessionConfiguration
        )
    }

    init(
        connectivityURLRequests: [URLRequest],
        responseValidator: (any ResponseValidator)? = nil,
        successThreshold: Percentage = Percentage(50.0),
        urlSessionConfiguration: URLSessionConfiguration = Self.defaultURLSessionConfiguration
    ) {
        self.connectivityURLRequests = connectivityURLRequests
        self.responseValidator = responseValidator ?? ResponseContainsStringValidator()
        self.successThreshold = successThreshold
        self.urlSessionConfiguration = urlSessionConfiguration
    }

    /// A copy of `urlSessionConfiguration` that never uses cached results, even
    /// when a custom configuration was supplied.
    var nonCachingURLSessionConfiguration: URLSessionConfiguration {
        // swiftlint:disable:next force_cast
        let output = urlSessionConfiguration.copy() as! URLSessionConfiguration
        output.requestCachePolicy = .reloadIgnoringCacheData
        output.urlCache = nil
        return output
    }
}
