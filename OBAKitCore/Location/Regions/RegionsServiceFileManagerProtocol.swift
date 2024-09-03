//
//  RegionsServiceFileManagerProtocol.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A protocol defining file management operations.
public protocol RegionsServiceFileManagerProtocol: AnyObject {
    
    /// Saves the Codable object to the specified directory with the given name.
    ///
    /// - Parameters:
    ///   - object: The Codable object to save.
    ///   - destination: The destination specifying where to save the object.
    func save<T: Codable>(_ object: T, to destination: URL) throws
    
    /// Loads a Codable object of the specified type from the file with the given URL.
    ///
    /// - Parameters:
    ///   - type: The type of the Codable object to load.
    ///   - fileURL: The URL of the file to load the object from.
    /// - Returns: The decoded Codable object.
    func load<T: Codable>(_ type: T.Type, from fileURL: URL) throws -> T
    
    /// Removes the file at the specified destination.
    ///
    /// - Parameters:
    ///   - destination: The destination specifying which file to remove.
    func remove(at destination: URL) throws
    
    /// Returns an array of URLs for the items at the specified URL.
    ///
    /// - Parameters:
    ///   - destination: The destination specifying where to load contents of.
    /// - Returns: An array of URLs for the items in the directory.
    func urls(at destination: URL) throws -> [URL]
    
}

extension FileManager: RegionsServiceFileManagerProtocol {
    
    /// Creates a directory at the specified URL if it doesn't already exist.
    private func createDirectoryIfNeeded(at url: URL) throws {
        guard !fileExists(atPath: url.path) else { return }
        try createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }
    
    public func urls(at destination: URL) throws -> [URL] {
        return try contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
    }
        
    public func load<T: Codable>(_ type: T.Type, from fileURL: URL) throws -> T {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    public func save<T: Codable>(_ object: T, to destination: URL) throws {
        let directoryURL = destination.deletingLastPathComponent()
        try createDirectoryIfNeeded(at: directoryURL)
        let encoded = try JSONEncoder().encode(object)
        try encoded.write(to: destination)
    }
        
    public func remove(at destination: URL) throws {
        guard fileExists(atPath: destination.path) else { return }
        try removeItem(at: destination)
    }
    
}
