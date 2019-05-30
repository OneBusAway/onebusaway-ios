//
//  MapSnapshotter.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/29/19.
//

import UIKit
import CoreLocation
import MapKit
import CocoaLumberjackSwift

public typealias MapSnapshotterCompletionHandler = ((UIImage?) -> Void)

/// Convenience helpers built on top of `MKMapSnapshotter` to simplify the process of creating a map screenshot.
public class MapSnapshotter: NSObject {
    private let size: CGSize
    private let coordinate: CLLocationCoordinate2D
    private let scale: CGFloat
    private let mapType: MKMapType
    private let zoomLevel: Int
    private let overlayColor: UIColor
    
    private var snapshotter: MKMapSnapshotter?
    
    public convenience init(size: CGSize, coordinate: CLLocationCoordinate2D) {
        let overlayColor = UIColor(white: 0.0, alpha: 0.4)
        self.init(size: size, coordinate: coordinate, screen: UIScreen.main, mapType: .mutedStandard, zoomLevel: 15, overlayColor: overlayColor)
    }

    public init(size: CGSize, coordinate: CLLocationCoordinate2D, screen: UIScreen, mapType: MKMapType, zoomLevel: Int, overlayColor: UIColor) {
        self.size = size
        self.coordinate = coordinate
        self.scale = screen.scale
        self.mapType = mapType
        self.zoomLevel = zoomLevel
        self.overlayColor = overlayColor
    }
    
    public func snapshot(stop: Stop, completion: @escaping MapSnapshotterCompletionHandler) {
        guard snapshotter == nil else {
            return
        }

        let options = MKMapSnapshotter.Options()
        options.size = size
        options.region = MapHelpers.coordinateRegionWith(center: coordinate, zoomLevel: zoomLevel, size: size)
        options.scale = scale
        options.mapType = mapType
        
        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { (snapshot, error) in
            guard
                error == nil,
                let image = snapshot?.image
            else {
                let error = String(describing: error)
                DDLogError("Failed to snapshot map: \(error)")
                completion(nil)
                self.snapshotter = nil
                return
            }
            
            // abxoxo - todo
//            let iconForStop = StopIconFactory.icon(for: stop, strokeColor: .black)
//            let annotatedImage = ImageHelpers.draw(iconForStop, onto: image, at: snapshot?.point(for: stop.coordinate))
            completion(image.overlay(color: self.overlayColor))
            self.snapshotter = nil
        }
        self.snapshotter = snapshotter
    }
    
    public func cancel() {
        snapshotter?.cancel()
        snapshotter = nil
    }
}
