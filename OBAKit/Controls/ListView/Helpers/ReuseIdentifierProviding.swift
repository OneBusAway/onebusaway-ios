//
//  ReuseIdentifierProviding.swift
//  OBAKit
//
//  Created by Alan Chu on 10/2/20.
//

public protocol ReuseIdentifierProviding: class {
    static var ReuseIdentifier: String { get }
}

extension ReuseIdentifierProviding {
    // Default implementation.
    static public var ReuseIdentifier: String {
        return "\(String(describing: self))_ReuseIdentifier"
    }
}
