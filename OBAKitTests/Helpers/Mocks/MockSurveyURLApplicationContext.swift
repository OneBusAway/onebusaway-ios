//
//  MockSurveyURLApplicationContext.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 19/02/2026.
//

import OBAKitCore
import CoreLocation

class MockSurveyURLApplicationContext: SurveyURLApplicationContext {

    var currentRegionIdentifier: RegionIdentifier?

    var currentCoordinate: CLLocationCoordinate2D?
    
}
