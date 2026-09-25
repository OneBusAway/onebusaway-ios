//
//  OnDemandServicesListView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import SwiftUI

/// Loads one agency's on-demand services (`services-for-agency`).
@MainActor final class OnDemandServicesListModel: ObservableObject {

    enum State: Equatable {
        case loading
        case loaded([OnDemandService])
        case failed(String)
    }

    @Published private(set) var state: State = .loading

    private let agencyID: String
    private let apiService: RESTAPIService?
    private let regionName: String?

    /// Bumped by every `load()`, so an earlier load that finishes late can tell
    /// it has been superseded and leave the newer result in place.
    private var loadGeneration = 0

    init(agencyID: String, apiService: RESTAPIService?, regionName: String?) {
        self.agencyID = agencyID
        self.apiService = apiService
        self.regionName = regionName
    }

    /// Safe to call again (retry, or the view reappearing); the list keeps
    /// showing its current state until the new result arrives.
    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let newState = await fetchState()
        // A cancelled load (the view went away) must not report the
        // cancellation as a failure; the next appearance loads again.
        guard generation == loadGeneration, !Task.isCancelled else { return }
        state = newState
    }

    private func fetchState() async -> State {
        guard let apiService else {
            return .failed(UnstructuredError("No API Service").localizedDescription)
        }
        // The map layer's probe already found no `/api/ondemand` here.
        if apiService.onDemandSupport.isKnownUnsupported(baseURL: apiService.baseURL) {
            return .loaded([])
        }
        do {
            let list = try await apiService.getOnDemandServices(agencyID: agencyID, geometryDetail: .simplified).list
            return .loaded(list.sorted { $0.id < $1.id })
        } catch APIError.requestNotFound(let response) where response.statusCode == 404 {
            // An unknown agency ID is a 404 (wiki §3.3); the agency was listed a
            // moment ago, so "no services" is the honest reading. A blank 200 is
            // also thrown as `requestNotFound` but is a bad response, not absence.
            return .loaded([])
        } catch {
            return .failed(ErrorClassifier.classify(error, regionName: regionName).localizedDescription)
        }
    }
}

/// The agency's on-demand services, one row each, pushing the service page.
struct OnDemandServicesListView: View {
    @ObservedObject var model: OnDemandServicesListModel
    let onSelect: (OnDemandService) -> Void

    init(model: OnDemandServicesListModel, onSelect: @escaping (OnDemandService) -> Void) {
        self.model = model
        self.onSelect = onSelect
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView()
            case .failed(let text):
                EmptyStateView(title: text, systemImage: "exclamationmark.triangle") {
                    Button(Strings.retry) {
                        Task { await model.load() }
                    }
                }
            case .loaded(let services) where services.isEmpty:
                EmptyStateView(title: Strings.onDemandNoServices, systemImage: "car")
            case .loaded(let services):
                List(services, id: \.id) { service in
                    Button {
                        onSelect(service)
                    } label: {
                        OnDemandServicesListRow(service: service)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .task { await model.load() }
    }
}

/// One service: its name, its kind, and a disclosure chevron.
private struct OnDemandServicesListRow: View {
    let service: OnDemandService

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name).foregroundStyle(.primary)
                Text(Strings.onDemandKindTitle(service.serviceKind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}
