//
//  AgenciesViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Combine
import OBAKitCore

/// Shared ViewModel for `AgenciesViewController`.
///
/// Owns the agency list fetch and sorting. The VC keeps the
/// `OBAListView`/`ProgressHUD`/`UIAlertController` wiring and routes errors
/// through `TaskController`.
@MainActor
final class AgenciesViewModel: ObservableObject {

    // MARK: - Published State

    /// Agencies sorted by name. Empty until `loadData()` completes successfully.
    @Published private(set) var agencies: [AgencyWithCoverage] = []

    // MARK: - Private

    private let application: Application

    // MARK: - Init

    init(application: Application) {
        self.application = application
    }

    // MARK: - Intent

    func loadData() async throws -> [AgencyWithCoverage] {
        guard let apiService = application.apiService else {
            throw UnstructuredError("No API Service")
        }

        let list = try await apiService.getAgenciesWithCoverage().list
        let sorted = list.sorted { $0.agency.name < $1.agency.name }
        agencies = sorted
        return sorted
    }
}
