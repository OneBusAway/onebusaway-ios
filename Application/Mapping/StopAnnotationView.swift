//
//  StopAnnotationView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/1/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit
import MapKit

public class StopAnnotationView: MKMarkerAnnotationView {

    public override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override public var annotation: MKAnnotation? {
        didSet {
            guard let annotation = annotation as? Stop else {
                return
            }

            glyphImage = Icons.transportIcon(from: annotation.prioritizedRouteTypeForDisplay)
        }
    }
}
