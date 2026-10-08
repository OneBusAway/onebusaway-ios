//
//  ResponseValidation.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 08/05/2020.
//

import Foundation

/// The contract for a response validator used to determine
/// connectivity based on a network response
public protocol ResponseValidator {
    
    /// Determines whether or not the response is valid
    /// and expected for a given `URL`
    ///
    /// - Parameter url: The `URL`, from which the response was fetched
    /// - Parameter _ response: The `URLResponse` returned by url
    /// - Parameter data: The data in the response returned by url
    func isResponseValid(_ response: URLResponse, data: Data) -> Bool
}
