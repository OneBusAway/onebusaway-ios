//
//  Localization.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

#if !SWIFT_PACKAGE
fileprivate class Localization: NSObject {}
#endif

internal func OBALoc(_ key: String, value: String, comment: String) -> String {
    #if SWIFT_PACKAGE
    return NSLocalizedString(key, tableName: nil, bundle: Bundle.module, value: value, comment: comment)
    #else
    return NSLocalizedString(key, tableName: nil, bundle: Bundle(for: Localization.self), value: value, comment: comment)
    #endif
}

internal func OBALoc(_ key: String, format: String, comment: String, _ arguments: CVarArg...) -> String {
    return String(format: OBALoc(key, value: format, comment: comment), arguments)
}
