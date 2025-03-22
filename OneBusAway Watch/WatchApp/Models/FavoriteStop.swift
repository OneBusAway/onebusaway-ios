//
//  FavoriteStop.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import Foundation

struct FavoriteStop: Identifiable, Codable {
    let id: String
    let stopId: String
    let name: String
    let routeIds: [String]
    let createdAt: Date
    
    init(stop: Stop) {
        self.id = UUID().uuidString
        self.stopId = stop.id
        self.name = stop.name
        self.routeIds = stop.routes
        self.createdAt = Date()
    }
    
    // Sort favorites by creation date (newest first)
    static func sortByCreationDate(_ lhs: FavoriteStop, _ rhs: FavoriteStop) -> Bool {
        return lhs.createdAt > rhs.createdAt
    }
    
    // Example favorite stop for previews
    static var example: FavoriteStop {
        FavoriteStop(stop: Stop.example)
    }
    
    // Additional examples for testing and previews
    static var examples: [FavoriteStop] {
        Stop.examples.map { FavoriteStop(stop: $0) }
    }
}

