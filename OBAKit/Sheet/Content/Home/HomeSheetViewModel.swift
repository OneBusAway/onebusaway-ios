//
//  HomeSheetViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore

// MARK: - HomeSheetViewModel

// TODO: Will own nearby-stops snapshot, bookmark groupings, and recent-stops
// state once the home sheet's content lands. Kept here so `HomeSheetView`'s
// `@StateObject` + `@autoclosure` plumbing is already in place.
@MainActor
final class HomeSheetViewModel: ObservableObject {

}
