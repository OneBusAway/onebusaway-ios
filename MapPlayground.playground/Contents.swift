/*:

 # OneBusAway Model and Networking Services

 */

import OBANetworkingKit
import MapKit
import CoreLocation
import PlaygroundSupport

PlaygroundPage.current.needsIndefiniteExecution = true

let baseURL = URL(string: "http://api.pugetsound.onebusaway.org")!
let apiKey = "test"
let uuid = UUID().uuidString
let appVersion = "playground"
let queue = OperationQueue()
queue.maxConcurrentOperationCount = 1
let apiService = RESTAPIService(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, networkQueue: queue)
let modelService = RESTAPIModelService(apiService: apiService, dataQueue: queue)

//: ## Agencies

apiService.getAgenciesWithCoverage { (op) in
    print("Agencies")
    for a in (op.entries ?? []) {
        print("• Agency: \(a)")
    }
}

//: ## Stops

let coordinate = CLLocationCoordinate2D(latitude: 47.6230999, longitude: -122.3132122)
let stopsOp = modelService.getStops(coordinate: coordinate)
stopsOp.completionBlock = {
    for stop in stopsOp.stops {
        print("• Stop: \(stop.name): \(stop)")
    }
}


//let appleParkWayCoordinates = CLLocationCoordinate2DMake(37.334922, -122.009033)
//
//// Now let's create a MKMapView
//let mapView = MKMapView(frame: CGRect(x:0, y:0, width:800, height:800))
//
//// Define a region for our map view
//var mapRegion = MKCoordinateRegion()
//
//let mapRegionSpan = 0.02
//mapRegion.center = appleParkWayCoordinates
//mapRegion.span.latitudeDelta = mapRegionSpan
//mapRegion.span.longitudeDelta = mapRegionSpan
//
//mapView.setRegion(mapRegion, animated: true)
//
//// Create a map annotation
//let annotation = MKPointAnnotation()
//annotation.coordinate = appleParkWayCoordinates
//annotation.title = "Apple Inc."
//annotation.subtitle = "One Apple Park Way, Cupertino, California."
//
//mapView.addAnnotation(annotation)
//
//// Add the created mapView to our Playground Live View
//PlaygroundPage.current.liveView = mapView
