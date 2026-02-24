import Foundation
import CoreLocation

class OTPService {
    static let shared = OTPService()
    private init() {}
    
    func planTrip(baseURL: URL, from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> [OTPItinerary] {
        var components = URLComponents(url: baseURL.appendingPathComponent("plan"), resolvingAgainstBaseURL: false)!
        
        components.queryItems = [
            URLQueryItem(name: "fromPlace", value: "\(from.latitude),\(from.longitude)"),
            URLQueryItem(name: "toPlace", value: "\(to.latitude),\(to.longitude)"),
            URLQueryItem(name: "time", value: formatTime(Date())),
            URLQueryItem(name: "date", value: formatDate(Date())),
            URLQueryItem(name: "mode", value: "TRANSIT,WALK"),
            URLQueryItem(name: "arriveBy", value: "false"),
            URLQueryItem(name: "wheelchair", value: "false"),
            URLQueryItem(name: "locale", value: "en")
        ]
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        let decoder = JSONDecoder()
        
        // Try multiple date strategies as different OTP servers use different formats
        let dateFormats = ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ"]
        let formatter = DateFormatter()
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let ms = try? container.decode(Int64.self) {
                return Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
            }
            let string = try container.decode(String.self)
            for format in dateFormats {
                formatter.dateFormat = format
                if let date = formatter.date(from: string) {
                    return date
                }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(string)")
        }
        
        let response = try decoder.decode(OTPPlanResponse.self, from: data)
        
        if let error = response.error {
            throw NSError(domain: "OTPError", code: error.id, userInfo: [NSLocalizedDescriptionKey: error.msg])
        }
        
        return response.plan?.itineraries ?? []
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: date).lowercased()
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy"
        return formatter.string(from: date)
    }
}
