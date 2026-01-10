//
//  FileManagerMock.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

@testable import OBAKitCore

class FileManagerMock: RegionsServiceFileManagerProtocol {
    var savedObjects: [String: Data] = [:]

    var existingPaths: Set<String> = []

    func save<T: Encodable>(_ object: T, to destination: URL) throws {
        let data = try JSONEncoder().encode(object)
        savedObjects[destination.path] = data
        existingPaths.insert(destination.path)

        existingPaths.insert(destination.deletingLastPathComponent().path)
    }

    func load<T: Decodable>(_ type: T.Type, from source: URL) throws -> T {
        guard let data = savedObjects[source.path] else {
            throw NSError(
                domain: "FileManagerMock", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "File not found: \(source.path)"])
        }
        return try JSONDecoder().decode(type, from: data)
    }

    func delete(at url: URL) throws {
        savedObjects.removeValue(forKey: url.path)
        existingPaths.remove(url.path)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        let prefix = url.path
        return savedObjects.keys
            .filter { $0.hasPrefix(prefix) && $0 != prefix }
            .map { URL(fileURLWithPath: $0) }
    }

    func createDirectory(at url: URL) throws {
        existingPaths.insert(url.path)
    }

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path) || savedObjects.keys.contains(path)
    }
}
