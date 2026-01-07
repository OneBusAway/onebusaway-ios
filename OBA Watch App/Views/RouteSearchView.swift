import SwiftUI
import CoreLocation
import Combine
import OBASharedCore

struct RouteSearchView: View {
    @StateObject private var viewModel: RouteSearchViewModel

    init(initialQuery: String) {
        _viewModel = StateObject(wrappedValue: RouteSearchViewModel(
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
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                    TextField("Search routes", text: $viewModel.query)
                        .onSubmit { viewModel.performSearch() }
                        .onChange(of: viewModel.query) { _, newValue in
                            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                viewModel.performSearch()
                            } else {
                                viewModel.routes = []
                            }
                        }
                        .font(.system(size: 16))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.15))
            )
            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))

            if viewModel.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            } else if !viewModel.routes.isEmpty {
                Section("Routes") {
                    ForEach(viewModel.routes, id: \.id) { route in
                        NavigationLink {
                            RouteDetailView(route: route)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "bus.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Color.green.gradient)
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    if let short = route.shortName, !short.isEmpty {
                                        Text(short)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    if let long = route.longName, !long.isEmpty {
                                        Text(long)
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                        )
                    }
                }
            } else if !viewModel.query.isEmpty && !viewModel.isLoading {
                Section {
                    VStack(spacing: 12) {
                        Spacer(minLength: 20)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No Routes Found")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Try a different search term.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer(minLength: 20)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("Routes")
        .onAppear {
            viewModel.performSearch()
        }
    }
}
