//
//  APIServiceProtocol.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import Foundation
import Combine

protocol APIServiceProtocol {
    func fetchNearbyStops(latitude: Double, longitude: Double) -> AnyPublisher<[Stop], APIError>
    func fetchArrivals(for stopId: String) -> AnyPublisher<[Arrival], APIError>
}

extension APIService: APIServiceProtocol {}

