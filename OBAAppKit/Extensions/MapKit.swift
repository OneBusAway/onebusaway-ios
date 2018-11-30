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
    /// - Parameters:
    ///   - newAnnotations: The new annotations of the specified type that will appear on the map.
    func updateAnnotations<T>(with newAnnotations: [T]) where T: MKAnnotation, T: Hashable {
        let oldAnnotations: Set<T> = Set(annotations.filter(type: T.self))
        let newAnnotations: Set<T> = Set(newAnnotations)

        // Which elements are in both sets?
        let overlap = newAnnotations.intersection(oldAnnotations)

        // Which elements have been completely removed?
        let removed = oldAnnotations.subtracting(overlap)

        // Which elements are completely new?
        let added = newAnnotations.subtracting(overlap)

        removeAnnotations(removed.allObjects)
        addAnnotations(added.allObjects)
    }
}
