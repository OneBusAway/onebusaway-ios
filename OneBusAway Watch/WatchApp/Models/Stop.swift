//
//  Stop.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import Foundation
import CoreLocation

struct Stop: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let direction: String
    let latitude: Double
    let longitude: Double
    let routes: [String]
    let distance: Double?
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    // Format distance in a human-readable way
    var formattedDistance: String? {
        guard let distance = distance else { return nil }
        
        if distance < 100 {
            return "\(Int(distance))m"
        } else if distance < 1000 {
            return "\(Int(distance))m"
        } else {
            let kilometers = distance / 1000
            return String(format: "%.1fkm", kilometers)
        }
    }
    
    static func == (lhs: Stop, rhs: Stop) -> Bool {
        lhs.id == rhs.id
    }
    
    static var example: Stop {
        Stop(
            id: "1_10914",
            name: "University District",
            direction: "Northbound",
            latitude: 47.6543,
            longitude: -122.3079,
            routes: ["45", "71", "73"],
            distance: 120
        )
    }
    
    // Additional examples for testing and previews
    static var examples: [Stop] {
        [
            Stop(
                id: "1_10914",
                name: "University District",
                direction: "Northbound",
                latitude: 47.6543,
                longitude: -122.3079,
                routes: ["45", "71", "73"],
                distance: 120
            ),
            Stop(
                id: "1_10917",
                name: "Pike Street & 4th Ave",
                direction: "Westbound",
                latitude: 47.6098,
                longitude: -122.3381,
                routes: ["10", "11", "43", "49"],
                distance: 350
            ),
            Stop(
                id: "1_10920",
                name: "Broadway & John St",
                direction: "Southbound",
                latitude: 47.6203,
                longitude: -122.3207,
                routes: ["9", "60"],
                distance: 780
            )
        ]
    }
}

