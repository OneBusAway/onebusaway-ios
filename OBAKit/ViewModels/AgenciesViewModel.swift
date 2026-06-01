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
/// Owns the agency list fetch, sorting, and error state. The VC keeps the
/// `OBAListView`/`ProgressHUD`/`UIAlertController` wiring.
@MainActor
final class AgenciesViewModel: ObservableObject {

    // MARK: - Published State

    /// Agencies sorted by name. Empty until `loadData()` completes successfully.
    @Published private(set) var agencies: [AgencyWithCoverage] = []

    /// `true` while `loadData()` is in flight.
    @Published private(set) var isLoading: Bool = false

    /// Non-nil when the most recent `loadData()` call failed.
    @Published private(set) var loadError: Error?

    // MARK: - Private

    private let application: Application

    // MARK: - Init

    init(application: Application) {
        self.application = application
    }

    // MARK: - Intent

    func loadData() async throws -> [AgencyWithCoverage] {
        guard let apiService = application.apiService else {
            let error = UnstructuredError("No API Service")
            loadError = error
            throw error
        }

        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let list = try await apiService.getAgenciesWithCoverage().list
            let sorted = list.sorted { $0.agency.name < $1.agency.name }
            agencies = sorted
            return sorted
        } catch {
            loadError = error
            throw error
        }
    }
}
