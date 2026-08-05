//
//  MapCameraInsetsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
@testable import OBAKit

@Suite(.serialized)
struct MapCameraInsetsTests {

    private let mapSize = CGSize(width: 390, height: 844)
    private let safeArea = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)

    @Test func `The bottom inset clears the sheet, not just the safe area`() {
        let insets = MapCameraInsets.insets(
            mapSize: mapSize,
            safeArea: safeArea,
            bottomObstruction: 400
        )

        // The whole point: framing into the covered half puts the trip behind the
        // sheet. 34pt of home-indicator inset is not enough on its own.
        #expect(insets.bottom > 400)
    }

    @Test func `The trailing inset clears the toolbar`() {
        // 42pt of buttons, 20pt off the trailing edge.
        let insets = MapCameraInsets.insets(
            mapSize: mapSize,
            safeArea: safeArea,
            rightObstruction: 62
        )

        #expect(insets.right > 62)
        #expect(insets.left < insets.right)
    }

    @Test func `A right-to-left layout puts the toolbar's inset on the left`() {
        // MapKit's edge padding is physical; "trailing" is not. A layout that
        // mirrors the toolbar has to mirror the inset with it or the framing
        // pushes content straight under the buttons.
        let insets = MapCameraInsets.insets(
            mapSize: mapSize,
            safeArea: safeArea,
            leftObstruction: 62
        )

        #expect(insets.left > 62)
        #expect(insets.right < insets.left)
    }

    @Test func `The safe area is the floor on every edge`() {
        let insets = MapCameraInsets.insets(mapSize: mapSize, safeArea: safeArea)

        #expect(insets.top > safeArea.top)
        #expect(insets.bottom > safeArea.bottom)
    }

    @Test func `An obstruction smaller than the safe area doesn't shrink the inset`() {
        let insets = MapCameraInsets.insets(
            mapSize: mapSize,
            safeArea: safeArea,
            bottomObstruction: 10
        )

        #expect(insets.bottom > safeArea.bottom)
    }

    @Test func `A sheet covering nearly the whole map still leaves a viewport`() {
        // MapKit given padding that exceeds its own bounds produces a nonsense
        // camera — a rect fitted into negative space. Scale the padding down
        // rather than hand it something it can't satisfy.
        let insets = MapCameraInsets.insets(
            mapSize: mapSize,
            safeArea: safeArea,
            bottomObstruction: 830
        )

        #expect(insets.top + insets.bottom <= mapSize.height - MapCameraInsets.minimumViewport.height)
        #expect(insets.bottom > insets.top)
    }

    @Test func `Clamping keeps the two insets in proportion`() {
        // Scaled, not truncated: the bottom obstruction is far bigger than the
        // top one, and a clamp that split the budget evenly would frame content
        // back under the sheet.
        let insets = MapCameraInsets.insets(
            mapSize: mapSize,
            safeArea: .zero,
            bottomObstruction: 1600,
            margin: 0
        )

        #expect(insets.top == 0)
        #expect(insets.bottom > 0)
    }

    @Test func `A map smaller than the minimum viewport gets no padding at all`() {
        let insets = MapCameraInsets.insets(
            mapSize: CGSize(width: 40, height: 40),
            safeArea: safeArea,
            bottomObstruction: 20
        )

        #expect(insets == .zero)
    }
}
