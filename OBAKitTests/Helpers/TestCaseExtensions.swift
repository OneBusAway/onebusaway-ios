//
//  TestCaseExtensions.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/19/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import XCTest
import OBATestHelpers
@testable import OBAKit

public extension OBATestCase {

    // MARK: - Obaco Model Service

    public var obacoModelService: ObacoModelService {
        return ObacoModelService(apiService: obacoService, dataQueue: OperationQueue())
    }

    // MARK: - Obaco API Service

    public var obacoRegionID: String {
        return "1"
    }

    public var obacoHost: String {
        return "alerts.example.com"
    }

    public var obacoURLString: String {
        return "https://\(obacoHost)"
    }

    public var obacoURL: URL {
        return URL(string: obacoURLString)!
    }

    public var obacoService: ObacoService {
        return ObacoService(baseURL: obacoURL, apiKey: "org.onebusaway.iphone.test", uuid: "12345-12345-12345-12345-12345", appVersion: "2018.12.31", regionID: obacoRegionID, networkQueue: OperationQueue())
    }
}

public extension OBATestCase {

    // MARK: - REST Model Service

    public var restModelService: RESTAPIModelService {
        return RESTAPIModelService(apiService: restService, dataQueue: OperationQueue())
    }

    // MARK: - REST API Service

    public var host: String {
        return "www.example.com"
    }

    public var baseURLString: String {
        return "https://\(host)"
    }

    public var baseURL: URL {
        return URL(string: baseURLString)!
    }

    public var restService: RESTAPIService {
        let url = URL(string: baseURLString)!
        return RESTAPIService(baseURL: url, apiKey: "org.onebusaway.iphone.test", uuid: "12345-12345-12345-12345-12345", appVersion: "2018.12.31")
    }
}

public extension OBATestCase {
    public var regionsModelService: RegionsModelService {
        return RegionsModelService(apiService: regionsAPIService, dataQueue: OperationQueue())
    }

    public var regionsAPIService: RegionsAPIService {
        return RegionsAPIService(baseURL: regionsURL, apiKey: "org.onebusaway.iphone.test", uuid: "12345-12345-12345-12345-12345", appVersion: "2018.12.31")
    }
}
