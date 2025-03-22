//
//  APIServiceFactory.swift
//  OBAKit
//
//  Created by Prince Yadav on 09/03/25.
//


import Foundation

class APIServiceFactory {
    static func getAPIService() -> APIServiceProtocol {
        if UserDefaults.standard.bool(forKey: "useMockData") {
            return MockAPIService()
        } else {
            return APIService.shared
        }
    }
}

