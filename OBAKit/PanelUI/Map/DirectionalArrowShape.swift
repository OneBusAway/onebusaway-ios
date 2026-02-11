//
//  DirectionalArrowShape.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A SwiftUI Shape that draws the directional triangle arrow for stop icons.
/// Matches the exact positioning from StopIconFactory's drawArrowImage method.
struct DirectionalArrowShape: Shape {
    let direction: Direction

    /// The size of the arrow (width x height for cardinal directions)
    private let arrowSize = CGSize(width: 12, height: 6)

    /// Translation applied to diagonal arrows to move them inward from corners
    private let cornerTranslation: CGFloat = 3.0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard direction != .unknown else { return path }

        let halfWidth = arrowSize.width / 2.0
        let rightLeg = arrowSize.width / sqrt(2.0)

        switch direction {
        case .n:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX + halfWidth, y: rect.minY + arrowSize.height))
            path.addLine(to: CGPoint(x: rect.midX - halfWidth, y: rect.minY + arrowSize.height))

        case .ne:
            var transform = CGAffineTransform(translationX: -cornerTranslation, y: cornerTranslation)
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY).applying(transform))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rightLeg).applying(transform))
            path.addLine(to: CGPoint(x: rect.maxX - rightLeg, y: rect.minY).applying(transform))

        case .nw:
            var transform = CGAffineTransform(translationX: cornerTranslation, y: cornerTranslation)
            path.move(to: CGPoint(x: rect.minX, y: rect.minY).applying(transform))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rightLeg).applying(transform))
            path.addLine(to: CGPoint(x: rect.minX + rightLeg, y: rect.minY).applying(transform))

        case .e:
            path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - arrowSize.height, y: rect.midY + halfWidth))
            path.addLine(to: CGPoint(x: rect.maxX - arrowSize.height, y: rect.midY - halfWidth))

        case .w:
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX + arrowSize.height, y: rect.midY + halfWidth))
            path.addLine(to: CGPoint(x: rect.minX + arrowSize.height, y: rect.midY - halfWidth))

        case .s:
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX + halfWidth, y: rect.maxY - arrowSize.height))
            path.addLine(to: CGPoint(x: rect.midX - halfWidth, y: rect.maxY - arrowSize.height))

        case .sw:
            var transform = CGAffineTransform(translationX: cornerTranslation, y: -cornerTranslation)
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY).applying(transform))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rightLeg).applying(transform))
            path.addLine(to: CGPoint(x: rect.minX + rightLeg, y: rect.maxY).applying(transform))

        case .se:
            var transform = CGAffineTransform(translationX: -cornerTranslation, y: -cornerTranslation)
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY).applying(transform))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rightLeg).applying(transform))
            path.addLine(to: CGPoint(x: rect.maxX - rightLeg, y: rect.maxY).applying(transform))

        case .unknown:
            break
        }

        path.closeSubpath()
        return path
    }
}
