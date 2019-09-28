//
//  MapHelpers.swift
//
//  Created by Johannes Rudolph on 10.05.17.
//  Based on http://troybrant.net/blog/2010/01/set-the-zoom-level-of-an-mkmapview/
//  https://gist.github.com/PowerPan/ab6de0fc246d29ec2372ec954c4d966d
//

import Foundation
import MapKit

class MapHelpers {

    private static let kMercatorRadius = 85445659.44705395
    private static let kMercatorOffset = 268435456.0

    class func coordinateRegionWith(center: CLLocationCoordinate2D, zoomLevel: Int, size: CGSize) -> MKCoordinateRegion {
        let span = coordinateSpanFrom(size: size, centerCoordinate: center, zoomLevel: zoomLevel)
        return MKCoordinateRegion(center: center, span: span)
    }

    class func longitudeToPixelSpaceX(longitude: Double) -> Double {
        return round(kMercatorOffset + kMercatorRadius * longitude * .pi / 180.0)
    }

    class func latitudeToPixelSpaceY(latitude: Double) -> Double {
        return round( Double(Float(kMercatorOffset) - Float(kMercatorRadius) * logf((1 + sinf(Float(latitude * .pi / 180.0))) / (1 - sinf(Float(latitude * .pi / 180.0)))) / Float(2.0)))
    }

    class func pixelSpaceXToLongitude(pixelX: Double) -> Double {
        return ((round(pixelX) - kMercatorOffset) / kMercatorRadius) * 180.0 / .pi
    }

    class func pixelSpaceYToLatitude(pixelY: Double) -> Double {
        return (.pi / 2.0 - 2.0 * atan(exp((round(pixelY) - kMercatorOffset) / kMercatorRadius))) * 180.0 / .pi
    }

    class func coordinateSpanFrom(size: CGSize, centerCoordinate: CLLocationCoordinate2D, zoomLevel: Int) -> MKCoordinateSpan {
        // convert center coordiate to pixel space
        let centerPixelX = self.longitudeToPixelSpaceX(longitude: centerCoordinate.longitude)
        let centerPixelY = self.latitudeToPixelSpaceY(latitude: centerCoordinate.latitude)

        // determine the scale value from the zoom level
        let zoomExponent = Double(20 - zoomLevel)
        let zoomScale = pow(2.0, zoomExponent)

        // scale the map’s size in pixel space
        let mapSizeInPixels = size
        let scaledMapWidth = Double(mapSizeInPixels.width) * zoomScale
        let scaledMapHeight = Double(mapSizeInPixels.height) * zoomScale

        // figure out the position of the top-left pixel
        let topLeftPixelX = centerPixelX - (scaledMapWidth / 2)
        let topLeftPixelY = centerPixelY - (scaledMapHeight / 2)

        // find delta between left and right longitudes
        let minLng = self.pixelSpaceXToLongitude(pixelX: topLeftPixelX)
        let maxLng = self.pixelSpaceXToLongitude(pixelX: topLeftPixelX + scaledMapWidth)
        let longitudeDelta = maxLng - minLng

        // find delta between top and bottom latitudes
        let minLat = self.pixelSpaceYToLatitude(pixelY: topLeftPixelY)
        let maxLat = self.pixelSpaceYToLatitude(pixelY: topLeftPixelY + scaledMapHeight)
        let latitudeDelta = -1 * (maxLat - minLat)

        // create and return the lat/lng span
        return MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
    }

    class func zoomLevel(centerCoordinate: CLLocationCoordinate2D, region: MKCoordinateRegion, pixelWidth: CGFloat) -> Double {
        let centerPixelSpaceX = longitudeToPixelSpaceX(longitude: centerCoordinate.longitude)

        let lonLeft = centerCoordinate.longitude - (region.span.longitudeDelta / 2)

        let leftPixelSpaceX = longitudeToPixelSpaceX(longitude: lonLeft)
        let pixelSpaceWidth = abs(centerPixelSpaceX - leftPixelSpaceX) * 2

        let zoomScale = pixelSpaceWidth / Double(pixelWidth)

        let zoomExponent = logC(val: zoomScale, forBase: 2)

        let zoomLevel = 20 - zoomExponent

        return zoomLevel
    }

    class func logC(val: Double, forBase base: Double) -> Double {
        return log(val)/log(base)
    }
}
