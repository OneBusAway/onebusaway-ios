# Launch map camera

On launch the map used GPS even when the selected region was somewhere else.
A rider in Taipei with Puget Sound selected opened on Taipei. The mismatch
bulletin existed on the UIKit map but did not move the camera. #615.

## Policy

`LaunchMapCamera.target(selectedRegion:userLocation:lastVisibleMapRect:)`:

1. GPS inside the selected region's `serviceRect` → zoom to the user (nearby stops).
2. GPS outside → last viewport *if that viewport still intersects the region*, otherwise the region's `serviceRect`. Show the existing region-mismatch bulletin.
3. No GPS → last viewport, or the region's `serviceRect`. No bulletin.

The locate button still centers on the user. Backgrounding for ten minutes does not recenter on GPS when the device is still outside the region.

## Surfaces

UIKit `MapViewController` and SwiftUI `MapPanelRootView` both call the same function. Tests do not load either view.

## Tests

`LaunchMapCameraTests`. Puget Sound + Seattle GPS → user. Puget Sound + Tampa GPS → Puget Sound rect.
