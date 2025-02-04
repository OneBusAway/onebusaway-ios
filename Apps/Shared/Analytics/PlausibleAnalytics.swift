import Foundation
import OBAKit
import AviaryInsights

class PlausibleAnalytics: NSObject {
    private let client: Plausible
    private var defaultProperties: [String: Any?] = [:]

    init(defaultDomainURL: URL, analyticsServerURL: URL) {
        self.client = Plausible(defaultDomain: defaultDomainURL.host!, serverURL: analyticsServerURL)
    }

    private func postEvent(pageURL: String, props: [String: Any?]) async {
        let event = Event(url: pageURL, props: buildProps(props))
        do {
            try await client.postEvent(event)
        } catch let error {
            print("Error: \(error)")
        }
    }

    func reportEvent(pageURL: String, label: String, value: Any?) async {
        await postEvent(pageURL: pageURL, props: [label: value])
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

    private func buildProps(_ moreProps: [String: Any?]) -> [String: Any?] {
        defaultProperties.merging(moreProps) { _, new in new }
    }
}
