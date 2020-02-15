//
//  MapSnapshotter.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/29/19.
//

import UIKit
import CoreLocation
import MapKit
import OBAKitCore

public typealias MapSnapshotterCompletionHandler = ((UIImage?) -> Void)

/// Convenience helpers built on top of `MKMapSnapshotter` to simplify the process of creating a map screenshot.
public class MapSnapshotter: NSObject {

    private let size: CGSize
    private let scale: CGFloat
    private let mapType: MKMapType
    private let zoomLevel: Int
    private let stopIconFactory: StopIconFactory

    public convenience init(size: CGSize, stopIconFactory: StopIconFactory) {
        self.init(size: size, screen: UIScreen.main, mapType: .mutedStandard, zoomLevel: 15, stopIconFactory: stopIconFactory)
    }

    public init(size: CGSize, screen: UIScreen, mapType: MKMapType, zoomLevel: Int, stopIconFactory: StopIconFactory) {
        self.size = size
        self.scale = screen.scale
        self.mapType = mapType
        self.zoomLevel = zoomLevel
        self.stopIconFactory = stopIconFactory
    }

    private func snapshotOptions(stop: Stop, traitCollection: UITraitCollection) -> MKMapSnapshotter.Options {
        let options = MKMapSnapshotter.Options()
        options.size = size
        options.region = MapHelpers.coordinateRegionWith(center: stop.coordinate, zoomLevel: zoomLevel, size: size)
        options.scale = scale
        options.mapType = mapType

        if #available(iOS 13.0, *) {
            options.traitCollection = traitCollection
        }

        return options
    }

    public func snapshot(stop: Stop, traitCollection: UITraitCollection, completion: @escaping MapSnapshotterCompletionHandler) {
        let options = snapshotOptions(stop: stop, traitCollection: traitCollection)

        let snapshot = MKMapSnapshotter(options: options)
        snapshot.start { [weak self] (snapshot, error) in
            guard let self = self else { return }

            guard error == nil, let snapshot = snapshot else {
                completion(nil)
                return
            }

            // Generate the stop icon.
            let stopIcon = self.stopIconFactory.buildIcon(for: stop, strokeColor: ThemeColors.shared.stopAnnotationStrokeColor, fillColor: ThemeColors.shared.stopAnnotationFillColor)

            // Calculate the point at which to draw the stop icon.
            // It needs to be shifted up by 1/2 the stop icon height
            // in order to draw it at the proper location.
            var point = snapshot.point(for: stop.coordinate)
            point.y -= (stopIcon.size.height / 2.0)

            // Render the composited image.
            var annotatedImage = UIImage.draw(image: stopIcon, onto: snapshot.image, at: point)

            if traitCollection.userInterfaceStyle == .light {
                annotatedImage = annotatedImage.darkened()
            }

            completion(annotatedImage)
        }
    }
}
