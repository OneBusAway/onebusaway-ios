//
//  StopAnnotationView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/1/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit
import MapKit

extension Stop: MKAnnotation {
    public var coordinate: CLLocationCoordinate2D {
        return location.coordinate
    }

    public var title: String? {
        //        return name
        return routes.map { $0.shortName }.prefix(5).joined(separator: ", ")
    }

    public var subtitle: String? {
        return Formatters.adjectiveFormOfCardinalDirection(direction)
    }
}

public class StopAnnotationView: MKMarkerAnnotationView {

    public override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        subtitleVisibility = .visible
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override public var annotation: MKAnnotation? {
        didSet {
            guard let annotation = annotation as? Stop else {
                return
            }

            clusteringIdentifier = annotation.direction

            markerTintColor = annotation.routes.first?.color

            glyphImage = Icons.transportIcon(from: annotation.prioritizedRouteTypeForDisplay)
        }
    }
}
