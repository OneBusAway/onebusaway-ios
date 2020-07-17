//
//  Animations.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

public typealias AnimationHandler = VoidBlock
public typealias AnimationCompletionCallback = ((Bool) -> Void)

/// Reusable animation helpers
class Animations: NSObject {

    public static let longAnimationDuration: TimeInterval = 2.0

    /// Performs the specified animations for the system's default animation duration.
    /// - Parameter animations: The animations to perform.
    public class func performAnimations(animations: @escaping AnimationHandler) {
        performAnimations(duration: UIView.inheritedAnimationDuration, animations: animations, completion: nil)
    }

    /// Performs the specified animations for the specified duration.
    /// - Parameter duration: The duration of the animation in seconds.
    /// - Parameter animations: The animations to perform.
    public class func performAnimations(duration: TimeInterval, animations: @escaping AnimationHandler) {
        UIView.animate(withDuration: duration, animations: animations, completion: nil)
    }

    /// Performs the specified animations for the specified duration, along with an optional completion callback.
    /// - Parameter duration: The duration of the animation in seconds.
    /// - Parameter animations: The animations to perform.
    /// - Parameter completion: Optional completion callback.
    public class func performAnimations(duration: TimeInterval, animations: @escaping AnimationHandler, completion: AnimationCompletionCallback?) {
        UIView.animate(withDuration: duration, animations: animations, completion: completion)
    }
}
