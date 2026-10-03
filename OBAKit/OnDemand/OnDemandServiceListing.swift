//
//  OnDemandServiceListing.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore

/// A service as every list of services shows it — the stop page's card, the
/// legacy stop page's section and the agency's service list: its name over
/// its kind.
struct OnDemandServiceListing: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String

    init(_ service: OnDemandService) {
        id = service.id
        title = service.name
        subtitle = Strings.onDemandKindTitle(service.serviceKind)
    }
}
