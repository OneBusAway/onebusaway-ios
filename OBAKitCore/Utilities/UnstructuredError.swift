//
//  UnstructuredError.swift
//  OBAKitCore
//
//  Created by Alan Chu on 1/6/23.
//

/// To surface obscure errors to the UI. `throw UnlocalizedError` is preferred over `print()` or returning an unclear `nil`.
public struct UnstructuredError: Error, LocalizedError {
    public var errorDescription: String?

    public init(_ description: String) {
        self.errorDescription = description
    }
}
