import Foundation
import Combine
import MapKit
import os.log

@MainActor
final class AddressSearchViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.onebusaway.watchkitapp", category: "AddressSearch")
    
    @Published var query: String
    @Published var results: [MKMapItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private var searchTask: Task<Void, Never>?
    private let searchCompleter = MKLocalSearchCompleter()

    init(initialQuery: String) {
        self.query = initialQuery
        self.searchCompleter.resultTypes = [.address, .pointOfInterest]
        logger.debug("Initialized AddressSearchViewModel with query: \(initialQuery)")
    }

    deinit {
        searchTask?.cancel()
    }

    func performSearch() {
        searchTask?.cancel()
        
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logger.debug("Empty search query, clearing results")
            results = []
            return
        }

        isLoading = true
        errorMessage = nil
        logger.debug("Starting search for: \(trimmed)")

        searchTask = Task {
            do {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = trimmed
                request.resultTypes = [.address, .pointOfInterest]
                
                logger.debug("Creating search request with query: \(trimmed)")
                let search = MKLocalSearch(request: request)
                let response = try await search.start()
                
                guard !Task.isCancelled else {
                    logger.debug("Search was cancelled")
                    return
                }
                
                logger.debug("Search completed. Found \(response.mapItems.count) results")
                if response.mapItems.isEmpty {
                    logger.warning("No results found for query: \(trimmed)")
                } else {
                    response.mapItems.forEach { item in
                        logger.debug("Found: \(item.name ?? "No name") - \(item.placemark.title ?? "No subtitle")")
                    }
                }
                
                self.results = response.mapItems
                self.isLoading = false
                
            } catch {
                guard !Task.isCancelled else { return }
                
                logger.error("Search failed: \(error.localizedDescription)")
                
                // Provide user-friendly error messages
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .notConnectedToInternet, .networkConnectionLost:
                        self.errorMessage = "No internet connection"
                    case .timedOut:
                        self.errorMessage = "Request timed out"
                    default:
                        self.errorMessage = "Unable to search. Please check your network connection."
                    }
                } else {
                    // For other errors, show a generic message
                    self.errorMessage = "Unable to search. Please try again."
                }
                self.isLoading = false
            }
        }
    }
}
