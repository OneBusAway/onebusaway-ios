//
//  MapKit.swift
//  OBAAppKit
//
//  Created by Aaron Brethorst on 11/27/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import MapKit

extension MKMapView {

    /// Replaces already-installed annotations of the specified type with the new annotations provided.
    ///
    ///
    /// - Parameters:
    ///   - newAnnotations: The new annotations of the specified type that will appear on the map.
    func updateAnnotations<T>(with newAnnotations: [T]) where T: MKAnnotation, T: Hashable {
        var oldAnnotations = Set(annotations.compactMap {$0 as? T})
        var newAnnotations: Set<T> = Set(newAnnotations)

        // Which elements are in both sets?
        let overlap = newAnnotations.intersection(oldAnnotations)

        // Remove the elements that no longer appear in the new set,
        // but leaving the ones that still appear.
        oldAnnotations.subtract(oldAnnotations.subtracting(overlap))
        newAnnotations.subtract(overlap)

        removeAnnotations(oldAnnotations.allObjects)
        addAnnotations(newAnnotations.allObjects)
    }
}
