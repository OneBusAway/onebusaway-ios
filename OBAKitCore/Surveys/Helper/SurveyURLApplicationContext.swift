//
//  SurveyURLApplicationContext.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 19/02/2026.
//

import CoreLocation

public protocol SurveyURLApplicationContext {

    var currentRegionIdentifier: Int? { get }

    var currentCoordinate: CLLocationCoordinate2D? { get }

}
