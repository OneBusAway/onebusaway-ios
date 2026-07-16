import Foundation
import OBAKit
import AviaryInsights

class PlausibleAnalytics: NSObject {
    private let client: Plausible
    private var defaultProperties: [String: (any Sendable)?] = [:]

    init(defaultDomainURL: URL, analyticsServerURL: URL) {
        self.client = Plausible(defaultDomain: defaultDomainURL.host!, serverURL: analyticsServerURL)
    }

    private func postEvent(pageURL: String, props: [String: (any Sendable)?]) async {
        let event = Event(url: pageURL, props: buildProps(props))
        do {
            try await client.postEvent(event)
        } catch let error {
            print("Error: \(error)")
        }
    }

    func reportEvent(pageURL: String, label: String, value: Any?) async {
        // The Analytics protocol is @objc, so `value` arrives as Any?; Plausible's
        // client requires Sendable props. Pass the known scalar types through
        // typed (numbers must stay numbers for server-side prop filtering) and
        // stringify only as a last resort.
        let sendableValue: (any Sendable)?
        switch value {
        case nil:
            sendableValue = nil
        case let string as String:
            sendableValue = string
        case let number as NSNumber:
            sendableValue = number
        default:
            sendableValue = value.map { String(describing: $0) }
        }
        await postEvent(pageURL: pageURL, props: [label: sendableValue])
    }

    func reportSearchQuery(_ query: String) async {
        await reportEvent(pageURL: "app://localhost/search", label: "query", value: query)
    }

    func reportStopViewed(name: String, id: String, stopDistance: String) async {
        await postEvent(pageURL: "app://localhost/stop", props: ["id": id, "distance": stopDistance])
    }

    public func setUserProperty(key: String, value: String?) {
        defaultProperties[key] = value
    }

    private func buildProps(_ moreProps: [String: (any Sendable)?]) -> [String: (any Sendable)?] {
        defaultProperties.merging(moreProps) { _, new in new }
    }
}
