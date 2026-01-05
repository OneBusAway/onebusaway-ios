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
        .navigationTitle("Search Places")
        .onAppear {
            if !viewModel.query.isEmpty {
                viewModel.performSearch()
            }
        }
        .alert("Location Access Required", isPresented: $showLocationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please enable location access in the Watch app settings to search for nearby places.")
        }
    }
    
    private var searchFieldSection: some View {
        Section {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Search for an address or place", text: $viewModel.query)
                    .onSubmit {
                        viewModel.performSearch()
                    }
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
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
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    private var loadingSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Searching...")
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
                Label("Search Error", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundColor(.red)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Try Again") {
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
            VStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                Text("No Results Found")
                    .font(.headline)
                
                Text("Try a different search term or check your spelling.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                #if DEBUG
                Button("Test with 'Seattle'") {
                    viewModel.query = "Seattle"
                    viewModel.performSearch()
                }
                .buttonStyle(.bordered)
                #endif
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
    }
    
    private var resultsSection: some View {
        Section(header: Text("Results")) {
            ForEach(Array(viewModel.results.enumerated()), id: \.element) { _, item in
                NavigationLink {
                    NearbyStopsAtLocationView(
                        title: item.name ?? viewModel.query,
                        coordinate: item.placemark.coordinate
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let name = item.name, !name.isEmpty {
                            Text(name)
                                .font(.headline)
                                .lineLimit(2)
                        }

                        if let title = item.placemark.title, title != item.name {
                            Text(title)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        if let address = item.placemark.formattedAddress, !address.isEmpty {
                            Text(address)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
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
