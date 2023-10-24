//
//  Agency.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MetaCodable
import GRDB

/// - SeeAlso: [OneBusAway Agency documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/elements/agency.html)
@Codable
public struct Agency: Identifiable, Hashable, FetchableRecord, PersistableRecord {
    public let id: String
    public let name: String

    public let disclaimer: String?
    public let email: String?

    @CodedAt("fareUrl") @CodedBy(URL.DecodeGarbageURL())
    public let fareURL: URL?

    @CodedAt("lang")
    public let language: String

    public let phone: String

    @CodedAt("privateService")
    public let isPrivateService: Bool

    @CodedAt("timezone")
    public let timeZone: String

    @CodedAt("url")
    public let agencyURL: URL
}
