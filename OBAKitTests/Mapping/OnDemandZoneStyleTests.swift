//
//  OnDemandZoneStyleTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics
import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `OnDemandZoneStyle` properties: fill alpha, line width, and stroke alpha across
/// region, street (normal, highlighted, dimmed), and halo states according to spec 2.3.
@Suite(.serialized)
final class OnDemandZoneStyleTests {

    // MARK: - Fill Alpha

    @Test func `Fill alpha is active only for region styles`() {
        let regionNormal = OnDemandZoneStyle.region(highlighted: false)
        let regionHighlighted = OnDemandZoneStyle.region(highlighted: true)
        #expect(regionNormal.fillAlpha == OnDemandZoneStyle.regionFillAlpha)
        #expect(regionHighlighted.fillAlpha == OnDemandZoneStyle.regionFillAlpha)
        #expect(regionNormal.fillAlpha == 0.2)

        let streetNormal = OnDemandZoneStyle.street(emphasis: .normal)
        let streetHighlighted = OnDemandZoneStyle.street(emphasis: .highlighted)
        let streetDimmed = OnDemandZoneStyle.street(emphasis: .dimmed)
        #expect(streetNormal.fillAlpha == 0.0)
        #expect(streetHighlighted.fillAlpha == 0.0)
        #expect(streetDimmed.fillAlpha == 0.0)

        let halo = OnDemandZoneStyle.halo
        #expect(halo.fillAlpha == 0.0)
    }

    // MARK: - Line Width

    @Test func `Line width matches expected point values across states`() {
        let regionNormal = OnDemandZoneStyle.region(highlighted: false)
        #expect(regionNormal.lineWidth == OnDemandZoneStyle.regionLineWidth)
        #expect(regionNormal.lineWidth == 2.0)

        let regionHighlighted = OnDemandZoneStyle.region(highlighted: true)
        #expect(regionHighlighted.lineWidth == OnDemandZoneStyle.emphasizedLineWidth)
        #expect(regionHighlighted.lineWidth == 4.0)

        let streetNormal = OnDemandZoneStyle.street(emphasis: .normal)
        let streetHighlighted = OnDemandZoneStyle.street(emphasis: .highlighted)
        let streetDimmed = OnDemandZoneStyle.street(emphasis: .dimmed)
        #expect(streetNormal.lineWidth == OnDemandZoneStyle.emphasizedLineWidth)
        #expect(streetHighlighted.lineWidth == OnDemandZoneStyle.emphasizedLineWidth)
        #expect(streetDimmed.lineWidth == OnDemandZoneStyle.emphasizedLineWidth)
        #expect(streetNormal.lineWidth == 4.0)

        let halo = OnDemandZoneStyle.halo
        #expect(halo.lineWidth == OnDemandZoneStyle.haloLineWidth)
        #expect(halo.lineWidth == 10.0)
    }

    // MARK: - Stroke Alpha

    @Test func `Stroke alpha differentiates halo, dimmed street, and full opacity`() {
        let halo = OnDemandZoneStyle.halo
        #expect(halo.strokeAlpha == OnDemandZoneStyle.haloStrokeAlpha)
        #expect(halo.strokeAlpha == 0.25)

        let streetDimmed = OnDemandZoneStyle.street(emphasis: .dimmed)
        #expect(streetDimmed.strokeAlpha == OnDemandZoneStyle.dimmedStrokeAlpha)
        #expect(streetDimmed.strokeAlpha == 0.6)

        let streetNormal = OnDemandZoneStyle.street(emphasis: .normal)
        let streetHighlighted = OnDemandZoneStyle.street(emphasis: .highlighted)
        #expect(streetNormal.strokeAlpha == 1.0)
        #expect(streetHighlighted.strokeAlpha == 1.0)

        let regionNormal = OnDemandZoneStyle.region(highlighted: false)
        let regionHighlighted = OnDemandZoneStyle.region(highlighted: true)
        #expect(regionNormal.strokeAlpha == 1.0)
        #expect(regionHighlighted.strokeAlpha == 1.0)
    }

    // MARK: - OnDemandZoneShape ObjectIdentifier Identity

    @Test func `OnDemandZoneShape id returns ObjectIdentifier of underlying polygon`() {
        let polygon1 = MKPolygon(coordinates: [
            CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
            CLLocationCoordinate2D(latitude: 47.7, longitude: -122.3),
            CLLocationCoordinate2D(latitude: 47.7, longitude: -122.2)
        ], count: 3)

        let polygon2 = MKPolygon(coordinates: [
            CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
            CLLocationCoordinate2D(latitude: 47.7, longitude: -122.3),
            CLLocationCoordinate2D(latitude: 47.7, longitude: -122.2)
        ], count: 3)

        let shape1 = OnDemandZoneShape(polygon: polygon1, color: .systemBlue, style: .region(highlighted: false))
        let shape2 = OnDemandZoneShape(polygon: polygon1, color: .systemRed, style: .halo)
        let shape3 = OnDemandZoneShape(polygon: polygon2, color: .systemBlue, style: .region(highlighted: false))

        #expect(shape1.id == ObjectIdentifier(polygon1))
        #expect(shape1.id == shape2.id, "Shapes wrapping the same polygon instance share identical id")
        #expect(shape1.id != shape3.id, "Shapes wrapping distinct polygon instances have distinct ids")
    }
}
