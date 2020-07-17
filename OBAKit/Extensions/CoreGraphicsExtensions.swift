//
//  CoreGraphicsExtensions.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics
import OBAKitCore

extension CGContext {
    /// Wraps the drawing code in `closure` with a push/pop pair of `saveGState()`/`restoreGState()`
    /// - Parameter closure: Your drawing code
    func pushPop(closure: VoidBlock) {
        saveGState()
        closure()
        restoreGState()
    }
}
