// PolylineTests.swift
//
// Copyright (c) 2015 Raphaël Mor
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import CoreLocation
import Testing
import XCTest

@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable colon mark comma redundant_discardable_let

private let COORD_EPSILON_1e5: Double = 0.00001
private let COORD_EPSILON_1e6: Double = 0.000001

@Suite(.serialized)
final class PolylineTests {

    // MARK:- Encoding Coordinates

    @Test func `Empty array should be empty string`() {
        let sut = Polyline(coordinates: [])
        #expect(sut.encodedPolyline == "")
    }

    @Test func `Zero should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: 0, longitude: 0)]

        let sut = Polyline(coordinates: coordinates)
        #expect(sut.encodedPolyline == "??")
    }

    @Test func `Minimal positive difference should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: 0.00001, longitude: 0.00001)]

        let sut = Polyline(coordinates: coordinates)
        #expect(sut.encodedPolyline == "AA")
    }

    @Test func `Low rounded values should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: 0.000014, longitude: 0.000014)]

        let sut = Polyline(coordinates: coordinates)
        #expect(sut.encodedPolyline == "AA")
    }

    @Test func `Mid rounded values should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: 0.000015, longitude: 0.000015)]

        let sut = Polyline(coordinates: coordinates)
        #expect(sut.encodedPolyline == "CC")
    }

    @Test func `High rounded values should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: 0.000016, longitude: 0.000016)]

        let sut = Polyline(coordinates: coordinates)
        #expect(sut.encodedPolyline == "CC")
    }

    @Test func `Minimal negative difference should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: -0.00001, longitude: -0.00001)]

        let sut = Polyline(coordinates: coordinates)
        #expect(sut.encodedPolyline == "@@")
    }

    @Test func `Low negative rounded values should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: -0.000014, longitude: -0.000014)]

        let sut = Polyline(coordinates: coordinates)
        #expect(sut.encodedPolyline == "@@")
    }

    @Test func `Mid negative rounded values should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: -0.000015, longitude: -0.000015)]

        let sut = Polyline(coordinates: coordinates)
        #expect(sut.encodedPolyline == "BB")
    }

    @Test func `High negative rounded values should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: -0.000016, longitude: -0.000016)]

        let sut = Polyline(coordinates: coordinates)
        #expect(sut.encodedPolyline == "BB")
    }

    @Test func `Small increment location array should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: 0.00001, longitude: 0.00001),
            CLLocationCoordinate2D(latitude: 0.00002, longitude: 0.00002)]

        let sut = Polyline(coordinates: coordinates)
        #expect(sut.encodedPolyline == "AAAA")
    }

    @Test func `Small decrement location array should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: 0.00001, longitude: 0.00001),
            CLLocationCoordinate2D(latitude: 0.00000, longitude: 0.00000)]

        let sut = Polyline(coordinates: coordinates)
        #expect(sut.encodedPolyline == "AA@@")
    }

    @Test func `Precision should be used properly in encoding`() {
        let coordinates = [CLLocationCoordinate2D(latitude: 10.1234567, longitude:10.1234567)]

        var sut = Polyline(coordinates: coordinates)
        #expect(sut.encodedPolyline == "sfx|@sfx|@")

        sut = Polyline(coordinates: coordinates, precision: 1e5)
        #expect(sut.encodedPolyline == "sfx|@sfx|@")

        sut = Polyline(coordinates: coordinates, precision: 1e6)
        #expect(sut.encodedPolyline == "ak{hRak{hR")
    }

    // MARK:- Decoding Coordinates

    @Test func `Empty polyline should be empty location array`() {
        let sut = Polyline(encodedPolyline: "")
        #expect(sut.coordinates != nil)
        #expect(sut.coordinates?.isEmpty == true)
    }

    @Test func `Invalid polyline should return nil`() {
        let sut = Polyline(encodedPolyline: "invalidPolylineString")
        #expect(sut.coordinates == nil)
    }

    @Test func `Valid polyline should return valid location array`() {
        let sut = Polyline(encodedPolyline: "_p~iF~ps|U_ulLnnqC_mqNvxq`@")

        let coordinates = sut.coordinates!

        #expect(coordinates.count == 3)
        expectClose(coordinates[0].latitude, 38.5, within: COORD_EPSILON_1e5)
        expectClose(coordinates[0].longitude, -120.2, within: COORD_EPSILON_1e5)
        expectClose(coordinates[1].latitude, 40.7, within: COORD_EPSILON_1e5)
        expectClose(coordinates[1].longitude, -120.95, within: COORD_EPSILON_1e5)
        expectClose(coordinates[2].latitude, 43.252, within: COORD_EPSILON_1e5)
        expectClose(coordinates[2].longitude, -126.453, within: COORD_EPSILON_1e5)
    }

    @Test func `Another valid polyline should return valid location array`() {
        let sut = Polyline(encodedPolyline: "_ojiHa`tLh{IdCw{Gwc_@")

        let coordinates = sut.coordinates!

        #expect(coordinates.count == 3)
        expectClose(coordinates[0].latitude, 48.8832, within: COORD_EPSILON_1e5)
        expectClose(coordinates[0].longitude, 2.23761, within: COORD_EPSILON_1e5)
        expectClose(coordinates[1].latitude, 48.82747, within: COORD_EPSILON_1e5)
        expectClose(coordinates[1].longitude, 2.23694, within: COORD_EPSILON_1e5)
        expectClose(coordinates[2].latitude, 48.87303, within: COORD_EPSILON_1e5)
        expectClose(coordinates[2].longitude, 2.40154, within: COORD_EPSILON_1e5)
    }

    @Test func `Precision should be used properly in decoding`() {

        var sut = Polyline(encodedPolyline: "sfx|@sfx|@")

        var coordinates = sut.coordinates!

        #expect(coordinates.count == 1)
        expectClose(coordinates[0].latitude, 10.1234567, within: COORD_EPSILON_1e5)

        sut = Polyline(encodedPolyline: "sfx|@sfx|@", precision: 1e5)

        coordinates = sut.coordinates!

        #expect(coordinates.count == 1)
        expectClose(coordinates[0].latitude, 10.1234567, within: COORD_EPSILON_1e5)

        sut = Polyline(encodedPolyline: "ak{hRak{hR", precision: 1e6)

        coordinates = sut.coordinates!

        #expect(coordinates.count == 1)
        expectClose(coordinates[0].latitude, 10.1234567, within: COORD_EPSILON_1e6)

    }

    // MARK:- Encoding levels

    @Test func `Emptylevels should be empty string`() {
        let sut = Polyline(locations: [], levels: [])

        #expect(sut.encodedLevels != nil)
        #expect(sut.encodedLevels! == "")
    }

    @Test func `Nillevels should be nil`() {
        let sut = Polyline(locations: [], levels: nil)

        #expect(sut.encodedLevels == nil)
    }

    @Test func `Validlevels should be encoded properly`() {
        let sut = Polyline(locations: [], levels: [0,1,2,3])

        #expect(sut.encodedLevels! == "?@AB")
    }

    // MARK:- Decoding levels

    @Test func `Empty levels should be empty level array`() {
        let sut = Polyline(encodedPolyline: "", encodedLevels: "")

        #expect(sut.levels != nil, "Level array should not be nil for empty string")
        #expect(sut.levels?.isEmpty == true)
    }

    @Test func `Invalid levels should return nil level array`() {
        let sut = Polyline(encodedPolyline: "", encodedLevels: "invalidLevelString")

        #expect(sut.levels == nil, "Level array should be nil for invalid string")
    }

    @Test func `Valid levels should return valid level array`() {
        let sut = Polyline(encodedPolyline: "", encodedLevels: "?@AB~F")

        if let resultArray = sut.levels {
            #expect(resultArray.count == 5)
            #expect(resultArray[0] == UInt32(0))
            #expect(resultArray[1] == UInt32(1))
            #expect(resultArray[2] == UInt32(2))
            #expect(resultArray[3] == UInt32(3))
            #expect(resultArray[4] == UInt32(255))

        } else {
            Issue.record("Valid Levels should be decoded properly")
        }
    }

    // MARK:- Encoding Locations
    @Test func `Locations array should be encoded properly`() {
        let locations = [CLLocation(latitude: 0.00001, longitude: 0.00001),
            CLLocation(latitude: 0.00000, longitude: 0.00000)]

        let sut = Polyline(locations: locations)
        #expect(sut.encodedPolyline == "AA@@")
    }

    // MARK:- Issues non-regression tests

    // Github Issue 1
    @Test func `Small negative differences should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: 37.32721043, longitude: 122.02685069),
            CLLocationCoordinate2D(latitude: 37.32727259, longitude: 122.02685280),
            CLLocationCoordinate2D(latitude: 37.32733398, longitude: 122.02684998)]

        let sut = Polyline(coordinates: coordinates)
        #expect(sut.encodedPolyline == "anybFyjxgVK?K?")
    }

    // Github Issue 3
    @Test func `Limit value is properly encoded`() {
        let sourceCoordinates = [CLLocationCoordinate2D(latitude: 0.00016, longitude: -0.00032)]

        let sut = Polyline(coordinates: sourceCoordinates)
        #expect(sut.encodedPolyline == "_@~@")
    }

    // Github issue 4
    @Test func `Precision is used properly`() {
        let encoded = "}gqefAridwgFrYEAhfA{@jDsAxBoBzBaDtB{iAX{c@EsU]uf@?_WR~@tPlTFfg@?jUNj|@eBtu@K?z]cAjLkDlJuFjGyG`IyCjIsAlM?|k@v@|dArQbv@k@jIpA?"
        let sut : [CLLocationCoordinate2D] = decodePolyline(encoded, precision: 1e6)!

        #expect(sut.count == 30)
        expectClose(sut[0].latitude, 37.332111, within: COORD_EPSILON_1e6)
        expectClose(sut[0].longitude, -122.030762, within: COORD_EPSILON_1e6)
    }

    // MARK:- README code samples

    @Test func `Coordinates encoding`() {
        let coordinates = [CLLocationCoordinate2D(latitude: 40.2349727, longitude: -3.7707443),
            CLLocationCoordinate2D(latitude: 44.3377999, longitude: 1.2112933)]

        let polyline = Polyline(coordinates: coordinates)
        #expect(polyline.encodedPolyline == "qkqtFbn_Vui`Xu`l]")
    }

    @Test func `Locations encoding`() {
        let locations = [CLLocation(latitude: 40.2349727, longitude: -3.7707443),
            CLLocation(latitude: 44.3377999, longitude: 1.2112933)]

        let polyline = Polyline(locations: locations)
        #expect(polyline.encodedPolyline == "qkqtFbn_Vui`Xu`l]")
    }

    @Test func `Level encoding`() {
        let coordinates = [CLLocationCoordinate2D(latitude: 40.2349727, longitude: -3.7707443),
            CLLocationCoordinate2D(latitude: 44.3377999, longitude: 1.2112933)]

        let levels: [UInt32] = [0,1,2,255]

        let polyline = Polyline(coordinates: coordinates, levels: levels)
        let _ : String? = polyline.encodedLevels
    }

    @Test func `Polyline decoding to coordinate`() {
        let polyline = Polyline(encodedPolyline: "qkqtFbn_Vui`Xu`l]")

        let decodedCoordinates: [CLLocationCoordinate2D]? = polyline.coordinates
        #expect(2 == decodedCoordinates!.count)
    }

    @Test func `Polyline decoding to locations`() {
        let polyline = Polyline(encodedPolyline: "qkqtFbn_Vui`Xu`l]")
        let decodedLocations: [CLLocation]? = polyline.locations

        #expect(2 == decodedLocations!.count)
    }

    @Test func `Level decoding`() {
        let polyline = Polyline(encodedPolyline: "qkqtFbn_Vui`Xu`l]", encodedLevels: "BA")
        let decodedLevels: [UInt32]? = polyline.levels

        #expect(2 == decodedLevels!.count)
    }

    @Test func precision() {
        // OSRM uses a 6 digit precision
        let _ = Polyline(encodedPolyline: "ak{hRak{hR", precision: 1e6)
    }

    @Test @available(tvOS 9.2, *)
    func `Polyline convertion to MK polyline`() {
        let polyline = Polyline(encodedPolyline: "qkqtFbn_Vui`Xu`l]")

        let mkPolyline = polyline.mkPolyline
        #expect(mkPolyline != nil)
        #expect(polyline.coordinates?.count == mkPolyline?.pointCount)
    }

    @Test @available(tvOS 9.2, *)
    func `Polyline convertion to MK polyline when encoding failed`() {
        let polyline = Polyline(encodedPolyline: "invalidPolylineString")
        let mkPolyline = polyline.mkPolyline
        #expect(mkPolyline == nil)
    }

    @Test @available(tvOS 9.2, *)
    func `Empty polyline convertion should be empty MK polyline`() {
        let polyline = Polyline(encodedPolyline: "")
        let mkPolyline = polyline.mkPolyline
        #expect(mkPolyline?.pointCount == 0)
    }
}

// MARK: - Performance

/// Stays on XCTest: Swift Testing has no equivalent of `measure`, so this is the
/// one test in this file that cannot become a `@Test`.
///
/// `nonisolated` is load-bearing, and it is not enough to merely omit
/// `@MainActor`. The target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so
/// an unannotated class is main-actor — and a main-actor XCTestCase does not
/// compile in the Swift 6 language mode: `XCTestCase`'s designated initializers
/// are nonisolated, and the synthesized overrides of `init()`,
/// `init(selector:)`, and `init(invocation:)` then mismatch. Opting this one
/// class out is what lets the whole target build in Swift 6 mode.
/// See docs/swift6-migration-plan.md, "Phase 4".
nonisolated final class PolylinePerformanceTests: XCTestCase {

    // Github Issue 8
    func testPerformances() {
        self.measure {
            let _ = Polyline(encodedPolyline:"wamrIo{gnAnG_CVIm@{NEsDFgAHu@^{C`@sC@_As@eWEoBIw@?QDYd@oB@Uv@eDHOViAPwB@_ACUGQIcDYiIsA{a@EcB?iBD]JyBV}C@GJKDOCUMOO@MLy@@}ATI@McEQsLCcC?}@De@BQNe@gDcEgBsCSa@Yy@QiAS{D?gAJ_APmAt@wD`@eDDq@?aCk@uTcBif@KiBSkBa@wBUu@u@yB}CmHo@oAw@kA_@g@y@s@w@i@eJiF}BcB_BwAoCsDaB_DwLsWaBaDyB}Dm@qA_AcDEOIq@Sy@AuBBu@LgAR}@|@kCt@}Ab@s@^g@hAoAb@]jBkAdHqDt@[~@QxABNEHEdA}@TYbAyATQXKdC[n@Sr@c@r@}@|BwE~@eBjAyAvAaAlCaBlCoAjC_A|Cu@lLeBnDcAxBy@xDmBlEkCvDcCrFaEHGxAg@nAYf@Cz@@hCd@zAHj@MTIf@c@T]Zo@b@iBFo@DgA?k@CgAEa@Y_BoBeHo@sC{@iFg@qBk@aDqBeJaBcG}E_P{AsFq@kCk@eCwAmIm@yEk@cFg@eHU{FAiBMaIIiHImDSwF_@gGc@wFq@_G]aCc@yCcAsFiAeFCQ}FgUcEaRmBsJ_C}M_BaK{A{KsC_V_Gil@WqDy@kJk@eHyAeSu@mL]{Ha@kNI_GEkKFcV?mHKeHK}Cg@eKa@cFWmCm@}Ea@uCcCqMm@mCmAoEq@wBuA{DuAmD_BiDeDkG]u@{AwC{BaFiA_Dy@gCiA_Em@cCeAyEo@oDs@yEq@wFm@iHIyA]qIQiJIiBAkBDg@Ru@DOJSFc@Bc@AUIg@M[]aDIsAWyUs@cx@MqJ[wL_@gLg@uLo@oLiAkRo@_Iy@kH_@uCy@}Ey@mDaBcGkDsIgBkDgAaBiDiEkBqB}AkAmCaBaImDkAs@{BeBaBkBmBqCaCoEy@sBw@}Bq@aCoA{EeA_Fg@qCsAaJ_@sC]}CUqC_@qFIuAUkGQeIG}QCsRFuD?_CDgIAoJMyMUaLq@mO[wF}@uMe@oFc@kDu@wF{@{E_BwH[wAmDkL{HaToC}HwA{DiAkD_AuDyA_Ig@}Dg@wCyCiTi@cDy@qGcAeGkHyi@oAcJwBoPwAyJs@yFy@kFoFy_@wBeNkA}HcEuZeBqKOyAs@kEk@qEq@qE[cBWkBoAmHsBeOCQCuD\\{Bd@_Cz@aAbDuC~HuH|BsCjBqCdAgBrAgC~AwDjA{ClA}DrAmFf@_Cz@yE^aCh@_EVaCl@eHPcCp@qNbAuPf@_HtA}Nr@gG|@}GfAmHbB_JrAqG~AoItFkX`@_Cd@uDb@iEb@mFTiEXmJDyDAkDGeD]sIe@oG_A_Ko@gGaA{HwAyJi@eDqAoHiCiMmByH_EmOoCkIaGyR]_A}AcF_AiD}@_DwAiHc@oCa@kDa@gGQaEEwJFoD^}Ib@gF^kCZeCT}@x@oE\\yAtCaOb@iCv@qGV{CXwEJwE\\gh@RaMZsIv@iMX}CXyBnAeIj@qCx@cDrCkJrIeWdAmDp@mC`AsE\\gC~AeJTqBJq@VeDd@yH`@qMZaNx@c\\DaCDiAjAmc@f@iOjDwy@RqC|AcR|@}HtAiK~@oGn@oD|Hoa@vAwJ\\oCl@sGb@cF`@kHF_C`@iKJiH?gJIiDCoBo@yRsBga@[cREsFBeU`@sOTwGFeC~@cWf@wK~@_WbAu[vEmuAfAoXHiLHmTKe]GiCYoHY_Ew@aH}CmSwBkQgBcPw@uKScFCwCHeHZcIx@iOf@cMF}Bn@s^v@k\\n@i[j@aRNwGf@aPNsHb@kP|@yWp@wPLiFLqCbBej@?m@f@sQnAi_@b@mNlAg[VqE\\yELaCLuAdAmKXqB`@{D~BcTn@aGDm@NiATqC@i@F_BCeBOqDK}@e@yCAUDYBQFKn@Er@Bt@Jb@ApBS`CHfFIpEo@lFgB`FwC|@u@vCoCxA}AdEsG`CgFr@kBnAcE`BcHd@uCb@{Dj@kHNsCrAq`@T}ZFSFkAR_BBQDIrBwB|Ca@fGKhADbLfBlD`AhCz@pExBtBpAxCtBt@b@dBr@|@TjBTnBCbAK^IxCeAp@]xC}Bv@u@rCuDxSo\\jBsCfnAgnB|TiZjD}Df@a@bD{BpDsBfIyCvh@yXzB}@pAYnEi@tGArD}@nOsFxJuFjLeIvF}C`GkEtBmA|AUn@AdQP~Fo@zBNtO~B`CV`@@b@I~@o@d@i@|@gB`IeT|C{Ib@aB^iB~DmS`AsD~@eCb@_AXe@lBmCjd@m`@rJcIxKgKbEcDzQmS|CyCfDiCbDmBjBy@tEaBfIqAnQmBbA[|AY|EgBdF_CxH_GtAmAbDsDd@o@|e@mt@vCaEhHqIbL{KvF}DrNmJl@El@c@v@g@\\s@~@o@tG_E\\AbEiCZe@dB}@hGsA^EdCBfC[zNy@`Di@fAM`@Mz@_@~UcIdHcB~CWdACx]nAnFl@pBh@fEvBjRfKrP~IvGlCfB\\rF^n@@~AKpC]fYeH`@EfECrDZ`Ej@xFp@rBFtBErAKnCe@~Ae@lBu@~HcEjF{BpJkDzJaDpCmAtDiC|BqBhEaFbCeCXChBuApBcAb@EJ@RBPEFQh@a@pBq@R@RJL@H?Jd@Xf@TFNATONSDKz@o@XMp@OTMpBUfAQjDoA|BwAv@o@j@]~A_BtIyJtEcGpC_EHKLNNEDKBOC[tDqFtAaBt@u@jAeAfBuALKfA_BjDoEfDiC~@a@BCYyDYsBCQz@aAHIP~@")
        }
    }
}
