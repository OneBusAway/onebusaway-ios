//
//  WeatherModelOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 11/9/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import OBAModelKit

public class WeatherModelOperation: Operation {
    var apiOperation: WeatherOperation?
    public private(set) var weatherForecast: WeatherForecast?

    public override func main() {
        super.main()

        guard let data = apiOperation?.data else {
            return
        }

        let decoder = JSONDecoder.obacoServiceDecoder()

        weatherForecast = try? decoder.decode(WeatherForecast.self, from: data)
    }
}
