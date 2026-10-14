//
//  OnDemandZoneThumbnailView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import OBAKitCore
import SwiftUI
import UIKit

/// One ring of full geometry in one service's colour.
struct OnDemandThumbnailRing: Equatable {
    let points: [CLLocationCoordinate2D]
    let color: UIColor

    static func == (lhs: OnDemandThumbnailRing, rhs: OnDemandThumbnailRing) -> Bool {
        lhs.color == rhs.color
            && lhs.points.count == rhs.points.count
            && zip(lhs.points, rhs.points).allSatisfy { $0.latitude == $1.latitude && $0.longitude == $1.longitude }
    }
}

/// Spec 3.4: the 2.7 projection (`OnDemandGeometry.LocalProjection`) centred
/// on the probe point, scaled so every ring vertex and the probe point fit in
/// the square with a 4 pt inset.
struct OnDemandThumbnailProjection {
    let centre: CGPoint
    private let projection: OnDemandGeometry.LocalProjection
    private let scale: Double

    init(rings: [OnDemandThumbnailRing], probePoint: CLLocationCoordinate2D, side: CGFloat, inset: CGFloat) {
        let projection = OnDemandGeometry.LocalProjection(origin: probePoint)
        self.projection = projection
        centre = CGPoint(x: side / 2, y: side / 2)

        let extent = rings.flatMap(\.points).reduce(0.0) { extent, coordinate in
            let projected = projection.project(coordinate)
            return max(extent, abs(projected.x), abs(projected.y))
        }
        let usable = max(Double(side / 2 - inset), 1)
        scale = extent > 0 ? usable / extent : 1
    }

    func point(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
        let projected = projection.project(coordinate)
        // Map y grows north; screen y grows down.
        return CGPoint(x: centre.x + projected.x * scale, y: centre.y - projected.y * scale)
    }
}

/// The bar's 56 pt thumbnail: a Canvas of the stack's rings around the probe
/// point, or a disc in the page's service colour with a car glyph until every
/// ring has loaded.
struct OnDemandZoneThumbnailView: View {
    let rings: [OnDemandThumbnailRing]?
    let probePoint: CLLocationCoordinate2D
    let placeholderColor: UIColor
    var side: CGFloat = 56

    private static let cornerRadius: CGFloat = 12
    private static let inset: CGFloat = 4
    private static let ringFillAlpha = 0.35
    private static let probeDotDiameter: CGFloat = 6
    private static let borderColor = Color.white.opacity(0.85)
    private static let borderWidth: CGFloat = 2

    var body: some View {
        if let rings {
            ringsCanvas(rings)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).strokeBorder(Self.borderColor, lineWidth: Self.borderWidth))
        } else {
            // Spec 3.4: until the geometry loads, a disc in the service colour.
            ZStack {
                Circle().fill(Color(uiColor: placeholderColor))
                Image(systemName: "car.fill").foregroundStyle(.white)
            }
            .frame(width: side, height: side)
            .overlay(Circle().strokeBorder(Self.borderColor, lineWidth: Self.borderWidth))
        }
    }

    private func ringsCanvas(_ rings: [OnDemandThumbnailRing]) -> some View {
        Canvas { context, size in
            let projection = OnDemandThumbnailProjection(rings: rings, probePoint: probePoint, side: size.width, inset: Self.inset)
            for ring in rings where ring.points.count >= 3 {
                var path = Path()
                path.addLines(ring.points.map(projection.point))
                path.closeSubpath()
                context.fill(path, with: .color(Color(uiColor: ring.color).opacity(Self.ringFillAlpha)))
                context.stroke(path, with: .color(Color(uiColor: ring.color)), lineWidth: 1)
            }
            let dot = CGRect(
                x: projection.centre.x - Self.probeDotDiameter / 2,
                y: projection.centre.y - Self.probeDotDiameter / 2,
                width: Self.probeDotDiameter,
                height: Self.probeDotDiameter
            )
            context.stroke(Path(ellipseIn: dot.insetBy(dx: -0.75, dy: -0.75)), with: .color(.white), lineWidth: 1.5)
            context.fill(Path(ellipseIn: dot), with: .color(Color(uiColor: .systemBlue)))
        }
        .background(Color(uiColor: .systemBackground).opacity(0.9))
    }
}
