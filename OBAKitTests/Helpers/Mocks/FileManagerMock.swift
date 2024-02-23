//
//  FileManagerMock.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

class RegionsServiceFileManagerMock: RegionsServiceFileManagerProtocol {
    
    var savedObjects: [String: Data] = [:]
    
    func save<T>(_ object: T, to destination: URL) throws where T : Decodable, T : Encodable {
        let encodedData = try JSONEncoder().encode(object)
        savedObjects[destination.path] = encodedData
    }
    
    func load<T>(_ type: T.Type, from fileURL: URL) throws -> T where T : Decodable {
        let data = savedObjects[fileURL.path, default: Data()]
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    func remove(at destination: URL) throws {
        savedObjects.removeValue(forKey: destination.path)
    }
    
    func urls(at destination: URL) throws -> [URL] {
        return []
    }
    
}
