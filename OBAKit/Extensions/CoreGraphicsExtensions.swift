//
//  CoreGraphicsExtensions.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/11/19.
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
