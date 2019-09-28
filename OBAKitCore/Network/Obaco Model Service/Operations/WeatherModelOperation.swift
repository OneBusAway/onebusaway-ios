//
//  WeatherModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/9/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class WeatherModelOperation: DataOperation {
    public var apiOperation: Operation?
    public private(set) var weatherForecast: WeatherForecast?

    public override func main() {
        super.main()

        guard
            let apiOperation = apiOperation as? WeatherOperation,
            let data = apiOperation.data
        else {
             return
        }

        let decoder = JSONDecoder.obacoServiceDecoder()

        weatherForecast = try? decoder.decode(WeatherForecast.self, from: data)
    }
}
