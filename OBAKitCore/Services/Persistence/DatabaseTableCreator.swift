//
//  OBA+GRDB.swift
//  OBAKitCore
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import GRDB

public protocol DatabaseTableCreator {

    /// Additional tables may be created by providing their types here. Tables specified here are created after `createTable(in:)` is called.
    static var additionalTableCreators: [DatabaseTableCreator.Type] { get }
    static func createTable(in database: Database) throws
}

extension DatabaseTableCreator {
    public static var additionalTableCreators: [DatabaseTableCreator.Type] { return [] }
}
