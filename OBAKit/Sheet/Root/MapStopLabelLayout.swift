//
//  MapStopLabelLayout.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics
import CoreLocation
import OBAKitCore

/// Where a stop's label sits relative to its pin, in screen terms.
///
/// The sides are absolute (left is always screen-left), not leading/trailing:
/// they come from geography, which doesn't flip in right-to-left languages.
enum MapStopLabelPlacement: Equatable, Sendable {
    case below
    case above
    case left
    case right
    case hidden
}

/// Places stop labels on the panel map so they don't overlap.
///
/// Every label goes below its pin when there's room, so the eye always knows
/// where to look. Only when that spot would overlap a pin or an already-placed
/// label does it move to the stop's *curbside* side: the side of the street the
/// stop is on, worked out from the direction vehicles travel past it. If that
/// overlaps too, the label is hidden. Pins are never moved or hidden for labels.
///
/// Pure geometry, so it can be tested without a map.
struct MapStopLabelLayout {
    struct Candidate: Equatable {
        let id: StopID
        /// The pin's center, in the map view's coordinate space.
        let center: CGPoint
        let labelSize: CGSize
        /// Which way vehicles travel past the stop, or `.unknown`.
        let direction: Direction
        /// Selected and bookmarked stops: placed first, and never hidden.
        let isRequired: Bool
    }

    /// Space between a pin's edge and its label, shared with `mapPinLabel`.
    static let gap: CGFloat = 2

    /// The pin's width and height.
    var pinSize: CGFloat = ThemeMetrics.defaultMapAnnotationSize
    /// Space between a pin's edge and its label.
    var gap: CGFloat = Self.gap

    /// - Parameters:
    ///   - candidates: Every stop on screen that wants a label.
    ///   - obstaclePins: Centers of pins with no label to place, which labels must still avoid.
    ///   - viewportCenter: Ties go to the stop nearest this point.
    ///   - heading: The map camera's heading in degrees, so curbside follows a rotated map.
    ///   - previous: The last layout. A label keeps its old spot while it still fits, so labels don't hop as the map moves.
    func layout(
        _ candidates: [Candidate],
        obstaclePins: [CGPoint] = [],
        viewportCenter: CGPoint,
        heading: Double = 0,
        previous: [StopID: MapStopLabelPlacement] = [:]
    ) -> [StopID: MapStopLabelPlacement] {
        var occupied = (candidates.map(\.center) + obstaclePins).map(pinRect(at:))
        var result: [StopID: MapStopLabelPlacement] = [:]

        let ordered = candidates.sorted { lhs, rhs in
            if lhs.isRequired != rhs.isRequired { return lhs.isRequired }
            let lhsDistance = lhs.center.squaredDistance(to: viewportCenter)
            let rhsDistance = rhs.center.squaredDistance(to: viewportCenter)
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            return lhs.id < rhs.id
        }

        for candidate in ordered {
            var options: [MapStopLabelPlacement] = [.below]
            if let curbside = Self.curbside(for: candidate.direction, heading: heading) {
                options.append(curbside)
            }
            // Keep the last spot first while it's still one of today's options;
            // a curbside spot from before the map rotated no longer faces the curb.
            if let last = previous[candidate.id], let index = options.firstIndex(of: last), index > 0 {
                options.swapAt(0, index)
            }

            let chosen = options.first { placement in
                let rect = labelRect(for: candidate, placement: placement)
                return !occupied.contains { $0.intersects(rect) }
            }

            if let chosen {
                result[candidate.id] = chosen
                occupied.append(labelRect(for: candidate, placement: chosen))
            } else if candidate.isRequired {
                // Required labels always draw, in the default spot.
                result[candidate.id] = .below
                occupied.append(labelRect(for: candidate, placement: .below))
            } else {
                result[candidate.id] = .hidden
            }
        }
        return result
    }

    /// The side of the pin that faces the curb, or `nil` when it can't be
    /// known or is the same as the default spot below the pin.
    ///
    /// Vehicles keep right, so a stop sits on the right of its direction of
    /// travel. That side is turned into screen space using the camera heading,
    /// then snapped to one of four sides. Anything more than 22.5° off vertical
    /// snaps to left or right, because labels are wide and short.
    static func curbside(for direction: Direction, heading: Double) -> MapStopLabelPlacement? {
        guard let bearing = direction.bearing else { return nil }
        let angle = CLLocationDirection(bearing + 90 - heading).radians
        let dx = sin(angle)
        let dy = -cos(angle)
        let placement: MapStopLabelPlacement
        if abs(dx) >= sin(CLLocationDirection(22.5).radians) {
            placement = dx > 0 ? .right : .left
        } else {
            placement = dy > 0 ? .below : .above
        }
        return placement == .below ? nil : placement
    }

    func pinRect(at center: CGPoint) -> CGRect {
        CGRect(x: center.x - pinSize / 2, y: center.y - pinSize / 2, width: pinSize, height: pinSize)
    }

    func labelRect(for candidate: Candidate, placement: MapStopLabelPlacement) -> CGRect {
        let size = candidate.labelSize
        let center = candidate.center
        let reach = pinSize / 2 + gap
        switch placement {
        case .below, .hidden:
            return CGRect(x: center.x - size.width / 2, y: center.y + reach, width: size.width, height: size.height)
        case .above:
            return CGRect(x: center.x - size.width / 2, y: center.y - reach - size.height, width: size.width, height: size.height)
        case .right:
            return CGRect(x: center.x + reach, y: center.y - size.height / 2, width: size.width, height: size.height)
        case .left:
            return CGRect(x: center.x - reach - size.width, y: center.y - size.height / 2, width: size.width, height: size.height)
        }
    }
}

extension Direction {
    /// Compass bearing in degrees (north is 0, east is 90), or `nil` when unknown.
    var bearing: Double? {
        switch self {
        case .n: return 0
        case .ne: return 45
        case .e: return 90
        case .se: return 135
        case .s: return 180
        case .sw: return 225
        case .w: return 270
        case .nw: return 315
        case .unknown: return nil
        }
    }
}

private extension CGPoint {
    func squaredDistance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }
}
