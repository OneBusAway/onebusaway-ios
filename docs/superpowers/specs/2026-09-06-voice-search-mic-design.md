# Voice search mic on map search (#1129)

## Decision (industry)

Google Maps puts a mic in the search bar and, after recognition, **runs the
search** (transcript briefly visible, then results). Apple Maps relies on
keyboard dictation. #1129 asks for an in-field mic that speeds lookup while
keeping keyboard fallback — that matches the Google pattern, not “fill only.”

## Behavior

1. Mic appears in `SearchSheetView`’s capsule (not the home tappable placeholder).
2. Tap → request speech + microphone auth → listen with partial results updating
   the query (suggestions refresh live).
3. On **final** result: set query, stop listening, run `SearchRequest` with:
   - `.stopNumber` when the utterance is mostly digits
   - `.route` when it starts with a route/bus cue (`route`, `bus`, …)
   - `.vehicleID` when it starts with a vehicle cue
   - `.address` otherwise (default destination lookup)
4. Tap mic again (or clear / close) cancels listening.
5. If speech is unavailable or permanently denied, hide the mic.

## Non-goals

- Siri shortcuts / App Intents
- Mic on the home capsule (it is not a text field)
- Auto-navigate without disambiguation when multiple results

## Privacy

`NSSpeechRecognitionUsageDescription` + `NSMicrophoneUsageDescription` in shared
Info.plist (brand-neutral), translated in each app’s `InfoPlist.strings`.
