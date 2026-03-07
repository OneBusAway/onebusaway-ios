//
//  RegionsServiceFileManagerProtocol.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public protocol RegionsServiceFileManagerProtocol: AnyObject {
    func save<T: Encodable>(_ object: T, to destination: URL) throws
    func load<T: Decodable>(_ type: T.Type, from source: URL) throws -> T
    func delete(at url: URL) throws
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func createDirectory(at url: URL) throws
    func fileExists(atPath path: String) -> Bool
}

public class RegionsServiceFileManager: RegionsServiceFileManagerProtocol {
    public init() {}

    public func save<T: Encodable>(_ object: T, to destination: URL) throws {
        let directoryURL = destination.deletingLastPathComponent()
        try createDirectory(at: directoryURL)
        let data = try JSONEncoder().encode(object)
        try data.write(to: destination)
    }

    public func load<T: Decodable>(_ type: T.Type, from source: URL) throws -> T {
        let data = try Data(contentsOf: source)
        return try JSONDecoder().decode(type, from: data)
    }

    public func delete(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
