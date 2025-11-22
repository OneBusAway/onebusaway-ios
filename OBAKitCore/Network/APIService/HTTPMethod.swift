//
//  HTTPMethod.swift
//  OBAKitCore
//
//  Created by Mohamed Sliem on 23/11/2025.
//

import Foundation

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
    case options = "OPTIONS"
}

extension HTTPMethod {
    public var value: String {
        return self.rawValue
    }
}
