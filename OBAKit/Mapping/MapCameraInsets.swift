//
//  MapCameraInsets.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import UIKit

/// Turns "what is covering the map" into the edge padding MapKit wants.
///
/// A map view fills the window, but a sheet sits over its bottom half and a
/// toolbar floats on one side. Framing a rect into the full bounds therefore
/// centres it under whatever is on top. Every caller of
/// `setVisibleMapRect(_:edgePadding:animated:)` that cares where its content
/// lands should build the padding here rather than guessing at constants.
nonisolated enum MapCameraInsets {

    /// Breathing room between the framed content and whatever bounds it.
    static let defaultMargin: CGFloat = ThemeMetrics.padding

    /// The smallest strip of map worth framing into. Padding is scaled back
    /// rather than allowed to consume the whole viewport — MapKit handed
    /// padding larger than its own bounds produces a nonsense camera.
    static let minimumViewport = CGSize(width: 120, height: 120)

    /// - Parameters:
    ///   - mapSize: The map view's bounds size.
    ///   - safeArea: The map view's safe-area insets — the floor on every edge.
    ///   - bottomObstruction: How far up from the map's bottom edge something
    ///     opaque reaches, measured in points. For a sheet that is its own
    ///     height plus the bottom safe area.
    ///   - leftObstruction: Same, from the left edge. `trailing` chrome lands
    ///     here in a right-to-left layout; MapKit's insets are physical.
    ///   - rightObstruction: Same, from the right edge.
    static func insets(
        mapSize: CGSize,
        safeArea: UIEdgeInsets,
        bottomObstruction: CGFloat = 0,
        leftObstruction: CGFloat = 0,
        rightObstruction: CGFloat = 0,
        margin: CGFloat = defaultMargin
    ) -> UIEdgeInsets {
        let top = safeArea.top + margin
        let bottom = max(safeArea.bottom, bottomObstruction) + margin
        let left = max(safeArea.left, leftObstruction) + margin
        let right = max(safeArea.right, rightObstruction) + margin

        let (clampedLeft, clampedRight) = clamped(
            near: left, far: right, available: mapSize.width, minimum: minimumViewport.width
        )
        let (clampedTop, clampedBottom) = clamped(
            near: top, far: bottom, available: mapSize.height, minimum: minimumViewport.height
        )

        return UIEdgeInsets(top: clampedTop, left: clampedLeft, bottom: clampedBottom, right: clampedRight)
    }

    /// Scales a pair of opposing insets down together when they don't both fit.
    ///
    /// Proportional rather than an even split: the obstructions are rarely
    /// symmetrical — a sheet covering half the map and a 34pt home indicator —
    /// and dividing the remaining budget evenly would frame content straight
    /// back under the larger one.
    private static func clamped(
        near: CGFloat, far: CGFloat, available: CGFloat, minimum: CGFloat
    ) -> (CGFloat, CGFloat) {
        let budget = available - minimum
        let total = near + far

        guard total > budget else { return (near, far) }
        guard budget > 0 else { return (0, 0) }

        // The second share is the remainder rather than a second multiplication:
        // scaling both leaves the pair a rounding error above the budget, which
        // is the whole thing this guard exists to prevent.
        let scaled = budget * (near / total)
        return (scaled, budget - scaled)
    }
}
