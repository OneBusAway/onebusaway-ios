import SwiftUI
import MapKit

struct AddressSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AddressSearchViewModel
    @State private var showLocationAlert = false
    
    // For testing different locations in simulator
    #if DEBUG
    @State private var testLocation: CLLocation? = nil
    #endif

    init(initialQuery: String = "") {
        _viewModel = StateObject(wrappedValue: AddressSearchViewModel(initialQuery: initialQuery))
    }

    var body: some View {
        List {
            searchFieldSection
            
            if viewModel.isLoading {
                loadingSection
            } else if let error = viewModel.errorMessage {
                errorSection(error: error)
            } else if viewModel.results.isEmpty {
                emptyStateSection
            } else {
                resultsSection
            }
        }
        .navigationTitle(OBALoc("address_search.title", value: "Search places", comment: "Address search title"))
        .onAppear {
            if !viewModel.query.isEmpty {
                viewModel.performSearch()
            }
        }
        .alert(OBALoc("address_search.location_required.title", value: "Location Access Required", comment: "Alert title"), isPresented: $showLocationAlert) {
            Button(OBALoc("common.ok", value: "OK", comment: "OK"), role: .cancel) {}
        } message: {
            Text(OBALoc("address_search.location_required.message", value: "Please enable location access in the Watch app settings to search for nearby places.", comment: "Alert message"))
        }
    }
    
    private var searchFieldSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
                
                TextField(OBALoc("address_search.placeholder", value: "Search places", comment: "Search field placeholder"), text: $viewModel.query)
                    .onSubmit {
                        viewModel.performSearch()
                    }
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.system(size: 16))
                    .onChange(of: viewModel.query) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            viewModel.performSearch()
                        } else {
                            viewModel.results = []
                        }
                    }
                
                if !viewModel.query.isEmpty {
                    Button(action: {
                        viewModel.query = ""
                        viewModel.results = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.15))
        )
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
    }
    
    private var loadingSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    ProgressView()
                    Text(OBALoc("address_search.searching", value: "Searching...", comment: "Searching status"))
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                Spacer()
            }
            .padding(.vertical, 16)
        }
    }
    
    private func errorSection(error: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(OBALoc("address_search.error.title", value: "Search Error", comment: "Error title"), systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundColor(.red)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(OBALoc("common.try_again", value: "Try Again", comment: "Retry button")) {
                    viewModel.performSearch()
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            }
            .padding(.vertical, 8)
        }
    }
    
    private var emptyStateSection: some View {
        Section {
            VStack(spacing: 12) {
                Spacer(minLength: 20)
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 30))
                    .foregroundColor(.secondary.opacity(0.5))
                
                Text(OBALoc("address_search.no_results.title", value: "No Results Found", comment: "No results title"))
                    .font(.system(size: 16, weight: .semibold))
                
                Text(OBALoc("address_search.no_results.subtitle", value: "Try a different search term or check your spelling.", comment: "No results subtitle"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                
                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }
    
    private var resultsSection: some View {
        Section(header: Text(OBALoc("address_search.results.header", value: "Results", comment: "Results header"))) {
            ForEach(Array(viewModel.results.enumerated()), id: \.element) { _, item in
                NavigationLink {
                    NearbyStopsAtLocationView(
                        title: item.name ?? viewModel.query,
                        coordinate: item.placemark.coordinate
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.blue.gradient)
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading, spacing: 2) {
                            if let name = item.name, !name.isEmpty {
                                Text(name)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }

                            let title = item.placemark.title ?? ""
                            let name = item.name ?? ""
                            
                            // Only show subtitle if it adds new information
                            if !title.isEmpty && title != name {
                                Text(title)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            } else if let address = item.placemark.formattedAddress, !address.isEmpty {
                                Text(address)
                                    .font(.system(size: 11))
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
    }
}

// MARK: - Preview

struct AddressSearchView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AddressSearchView()
        }
        
        NavigationStack {
            AddressSearchView()
        }
        .previewDisplayName("With Results")
        .onAppear {
            // This is just for preview purposes
            let viewModel = AddressSearchViewModel(initialQuery: "Coffee")
            viewModel.results = [
                MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)))
            ]
            _ = viewModel // Silence warning
        }
    }
}

// MARK: - Extensions

private extension MKPlacemark {
    var formattedAddress: String? {
        var components = [String]()
        
        if let thoroughfare = self.thoroughfare {
            components.append(thoroughfare)
        }
        if let locality = self.locality {
            components.append(locality)
        }
        if let administrativeArea = self.administrativeArea {
            components.append(administrativeArea)
        }
        if let postalCode = self.postalCode {
            components.append(postalCode)
        }
        if let country = self.country {
            components.append(country)
        }
        
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }
}
