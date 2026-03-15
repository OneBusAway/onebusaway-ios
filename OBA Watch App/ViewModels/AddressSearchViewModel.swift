import Foundation
import Combine
import MapKit
import OBAKitCore

@MainActor
final class AddressSearchViewModel: ObservableObject {
    @Published var query: String
    @Published var results: [MKMapItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private var searchTask: Task<Void, Never>?
    private let searchCompleter = MKLocalSearchCompleter()

    init(initialQuery: String) {
        self.query = initialQuery
        self.searchCompleter.resultTypes = [.address, .pointOfInterest]
    }

    deinit {
        searchTask?.cancel()
    }

    func performSearch() {
        searchTask?.cancel()
        
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }

        isLoading = true
        errorMessage = nil

        searchTask = Task {
            do {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = trimmed
                request.resultTypes = [.address, .pointOfInterest]
                
                let search = MKLocalSearch(request: request)
                let response = try await search.start()
                
                guard !Task.isCancelled else {
                    return
                }
                
                self.results = response.mapItems
                self.isLoading = false
                
            } catch {
                guard !Task.isCancelled else { return }
                
                Logger.error("Search failed: \(error)")
                
                // Provide user-friendly error messages
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .notConnectedToInternet, .networkConnectionLost:
                        self.errorMessage = OBALoc("search.error.no_internet", value: "No internet connection", comment: "No internet error message")
                    case .timedOut:
                        self.errorMessage = OBALoc("search.error.timed_out", value: "Request timed out", comment: "Request timed out error message")
                    default:
                        self.errorMessage = OBALoc("search.error.network_issue", value: "Unable to search. Please check your network connection.", comment: "Generic network error message")
                    }
                } else {
                    // For other errors, show a generic message
                    self.errorMessage = OBALoc("search.error.generic", value: "Unable to search. Please try again.", comment: "Generic search error message")
                }
                self.isLoading = false
            }
        }
    }
}
