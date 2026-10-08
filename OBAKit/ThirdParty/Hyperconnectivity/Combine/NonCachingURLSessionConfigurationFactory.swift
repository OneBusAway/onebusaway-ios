//
//  NonCachingURLSessionConfigurationFactory.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 20/03/2022.
//

import Foundation

struct NonCachingURLSessionConfigurationFactory {
    func urlSessionConfiguration(from input: URLSessionConfiguration) -> URLSessionConfiguration {
        // Ensure that we never use cached results, including where using a custom `URLSessionConfiguration`.
        let output = input.copy() as! URLSessionConfiguration
        output.requestCachePolicy = .reloadIgnoringCacheData
        output.urlCache = nil
        return output
    }
}
