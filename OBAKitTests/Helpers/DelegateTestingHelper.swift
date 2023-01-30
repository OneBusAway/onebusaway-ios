//
//  DelegateTestingHelper.swift
//  OBAKitTests
//
//  Created by Alan Chu on 1/12/23.
//

import XCTest

/// Helpers for testing delegates.
enum DelegateTestingHelper {

    /// An enum for indicating whether a delegate method was called, and with what method parameters.
    ///
    /// The example below describes how to use this in an ``XCTestCase`` to compare the expected value of a delegate call:
    /// ```
    /// private class LocationServiceTestDelegate: LocationServiceDelegate {
    ///     // You will need to manually implement each delegate method to test.
    ///     private(set) var locationServiceDidUpdateLocation: DelegateTestingHelper.DidCallDelegateMethod<CLLocation?> = . didNotCall
    ///
    ///     func locationService(_ locationService: LocationService, didUpdateLocation newLocation: CLLocation?) {
    ///         locationServiceDidUpdateLocation = .called(newLocation)
    ///     }
    /// }
    ///
    /// func testLocationDelegateCallsDidUpdateLocation() async {
    ///     let myCurrentLocation: CLLocation /* ... */
    ///     let delegate = LocationServiceTestDelegate()
    ///     let locationService = LocationService(delegate: delegate)
    ///
    ///     // We are testing that updateLocation() informs the delegate of an updated location.
    ///     await locationService.updateLocation()
    ///
    ///     // Use XCTAssertDidCallDelegateMethodWithValue to check the delegate was called
    ///     // with the expected value.
    ///     XCTAssertDidCallDelegateMethodWithValue(
    ///         delegate.locationServiceDidUpdateLocation,
    ///         myCurrentLocation,
    ///         "Expected LocationService to inform delegate with the updated location."
    ///     )
    /// }
    /// ```
    ///
    /// - To test a delegate method with no parameters, use `DidCallDelegateMethod<Void>`. A delegate method that includes its caller as a parameter should not considered a parameter (in the above example, `locationService(locationService:didUpdateLocation:)` only used `didUpdateLocation`).
    /// - To test a delegate method with multiple parameters, use a tuple. All types of the tuple must conform to ``Equatable`` to use `XCTAssertDidCallDelegateMethodWithValue`.
    ///
    /// - To test whether a delegate method was called, regardless of the parameter values:
    /// ```
    /// XCTAssertTrue(delegate.locationServiceDidUpdateLocation.didCall, "Expected the LocationService to inform delegate of an updated location.")
    /// ```
    enum DidCallDelegateMethod<T> {
        case didNotCall
        case called(T)

        var didCall: Bool {
            switch self {
            case .didNotCall: return false
            case .called: return true
            }
        }
    }
}

extension DelegateTestingHelper.DidCallDelegateMethod: Equatable where T: Equatable {
    static func == (lhs: DelegateTestingHelper.DidCallDelegateMethod<T>, rhs: DelegateTestingHelper.DidCallDelegateMethod<T>) -> Bool {
        switch (lhs, rhs) {
        case (.didNotCall, .didNotCall):
            return false
        case (_, .didNotCall):
            return false
        case (.didNotCall, _):
            return false
        case (.called(let lhsValue), .called(let rhsValue)):
            return lhsValue == rhsValue
        }
    }
}

func XCTAssertDidCallDelegateMethodWithValue<Value: Equatable>(
    _ didCall: DelegateTestingHelper.DidCallDelegateMethod<Value>,
    _ expectedValue: Value,
    _ message: String = ""
) {
    XCTAssertEqual(didCall, .called(expectedValue), message)
}
