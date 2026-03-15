//
//  ExternalSurveyURLBuilderProtocol.swift
//  OBAKitCore
//
//  Created by Mohamed Sliem on 18/02/2026.
//

import Foundation

public protocol ExternalSurveyURLBuilderProtocol {

    func buildURL(for survey: Survey, stop: Stop?) -> URL?

}
