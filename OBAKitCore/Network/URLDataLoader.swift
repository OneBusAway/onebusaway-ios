//
//  URLDataLoader.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 5/1/20.
//

import Foundation

public protocol URLDataLoader: NSObjectProtocol {
    func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask
}

extension URLSession: URLDataLoader { }
