import SwiftUI
import CoreLocation
import OBAKitCore

struct StopSearchResultsView: View {
    @StateObject private var viewModel: StopSearchViewModel

    init(initialQuery: String) {
        _viewModel = StateObject(wrappedValue: StopSearchViewModel(
            initialQuery: initialQuery,
            apiClient: WatchAppState.shared.apiClient,
            locationProvider: { WatchAppState.shared.currentLocation }
        ))
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                    TextField(OBALoc("stop_search.placeholder", value: "Search stops", comment: "Search stops placeholder"), text: $viewModel.query)
                        .font(.system(size: 16))
                        .padding(.vertical, 8)
                        .onSubmit { viewModel.performSearch() }
                        .onChange(of: viewModel.query) { _, newValue in
                            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                viewModel.performSearch()
                            } else {
                                viewModel.stops = []
                            }
                        }
                }
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.15))
            )

            if viewModel.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            } else if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            } else if !viewModel.stops.isEmpty {
                Section {
                    ForEach(viewModel.stops) { stop in
                        NavigationLink {
                            StopArrivalsView(stopID: stop.id, stopName: stop.name)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "signpost.right.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Color.orange.gradient)
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stop.name)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    
                                    if let code = stop.code {
                                        Text(String(format: OBALoc("stop_search.stop_code_format", value: "Stop %@", comment: "Stop code format"), code))
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                        )
                    }
                }
            } else if viewModel.stops.isEmpty && !viewModel.isLoading {
                Section {
                    VStack(spacing: 12) {
                        Spacer(minLength: 20)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(OBALoc("stop_search.empty.title", value: "No Stops Found", comment: "No stops found empty state title"))
                            .font(.system(size: 16, weight: .semibold))
                        Text(OBALoc("stop_search.empty.subtitle", value: "Try a different search term.", comment: "No stops found empty state subtitle"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer(minLength: 20)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle(OBALoc("stop_search.nav_title", value: "Stops", comment: "Stop search navigation title"))
        .onAppear {
            viewModel.performSearch()
        }
    }
}
