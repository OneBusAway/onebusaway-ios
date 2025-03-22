//
//  APIError.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//

import Foundation
import Combine

enum APIError: Error {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case serverError(Int)
    case sslError
    case unknown
    
    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .serverError(let statusCode):
            return "Server error: \(statusCode)"
        case .sslError:
            return "Network error: An SSL error has occurred and a secure connection to the server cannot be made."
        case .unknown:
            return "Unknown error occurred"
        }
    }
}

class APIService {
    static let shared = APIService()
    
    private let baseURL = "https://api.onebusaway.org/api/where"
    private var apiKey: String {
        return UserDefaults.standard.string(forKey: "apiKey") ?? "TEST"
    }
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.urlCache = URLCache(memoryCapacity: 20_000_000, diskCapacity: 100_000_000, diskPath: "onebusaway_cache")
        return URLSession(configuration: config)
    }()
    
    private init() {}
    
    func fetchNearbyStops(latitude: Double, longitude: Double) -> AnyPublisher<[Stop], APIError> {
        let endpoint = "/stops-for-location.json"
        let queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "lat", value: "\(latitude)"),
            URLQueryItem(name: "lon", value: "\(longitude)"),
            URLQueryItem(name: "radius", value: "500")
        ]
        
        return makeRequest(endpoint: endpoint, queryItems: queryItems)
            .decode(type: StopsResponse.self, decoder: JSONDecoder())
            .map { $0.data.stops }
            .mapError(handleError)
            .eraseToAnyPublisher()
    }
    
    func fetchArrivals(for stopId: String) -> AnyPublisher<[Arrival], APIError> {
        let endpoint = "/arrivals-and-departures-for-stop/\(stopId).json"
        let queryItems = [
            URLQueryItem(name: "key", value: apiKey)
        ]
        
        return makeRequest(endpoint: endpoint, queryItems: queryItems)
            .decode(type: ArrivalsResponse.self, decoder: JSONDecoder())
            .map { $0.data.entry.arrivalsAndDepartures }
            .mapError(handleError)
            .eraseToAnyPublisher()
    }
    
    private func makeRequest(endpoint: String, queryItems: [URLQueryItem]) -> AnyPublisher<Data, APIError> {
        var components = URLComponents(string: baseURL + endpoint)
        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        
        return session.dataTaskPublisher(for: request)
            .mapError { error in
                if let urlError = error as? URLError {
                    return self.mapURLError(urlError)
                }
                return .networkError(error)
            }
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.unknown
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw APIError.serverError(httpResponse.statusCode)
                }
                
                return data
            }
            .mapError(handleError)
            .eraseToAnyPublisher()
    }
    
    private func mapURLError(_ error: URLError) -> APIError {
        switch error.code {
        case .secureConnectionFailed, .serverCertificateUntrusted,
             .clientCertificateRejected, .clientCertificateRequired:
            return .sslError
        default:
            return .networkError(error)
        }
    }
    
    private func handleError(_ error: Error) -> APIError {
        if let apiError = error as? APIError {
            return apiError
        } else if let decodingError = error as? DecodingError {
            return .decodingError(decodingError)
        } else {
            return .networkError(error)
        }
    }
}

// MARK: - Response Models

struct StopsResponse: Decodable {
    let data: StopsData
}

struct StopsData: Decodable {
    let stops: [Stop]
}

struct ArrivalsResponse: Decodable {
    let data: ArrivalsData
}

struct ArrivalsData: Decodable {
    let entry: ArrivalsEntry
}

struct ArrivalsEntry: Decodable {
    let arrivalsAndDepartures: [Arrival]
}
