# App Store screenshots

Everything needed to regenerate the App Store screenshot slides from the
simulator. The slide list and captions are in `screenshots.json`; the listing
text (description, keywords, promotional text) is in `listing.md`.

```bash
scripts/generate_project OneBusAway        # required first
scripts/app_store_screenshots              # capture → export → frame → compose
```

The finished slides land in `build/app-store-screenshots/slides/`, one PNG per
slide at 1206 × 2622 (the 6.3" iPhone size). Add `--size 1320x2868` for the 6.9"
size; the layout scales with the canvas.

## How it works

1. **Capture.** `OBAKitUITests/AppStoreScreenshotUITests` has one test per
   slide. Each walks to its screen and attaches a full-screen capture named
   after the slide (`01-stop-arrivals`, …). The script runs them on the newest
   "iPhone NN Pro" simulator (override with `SCREENSHOT_UDID`), after pinning
   the status bar to 9:41 and granting location. The test sets the simulated
   location to Capitol Hill, Seattle.
2. **Export.** `scripts/app_store/export_screenshots.py` pulls the named
   attachments out of the `.xcresult` bundle into `raw/`.
3. **Frame.** [frames-cli](https://github.com/viticci/frames-cli) adds the
   iPhone 17 Pro bezel in Cosmic Orange, into `framed/`.
4. **Compose.** `scripts/app_store/compose_screenshots.py` puts each framed
   capture on the `#68AD0B` background under its caption, in SF Pro Display
   Bold, into `slides/`. The proportions come from the hand-made 2025 set.

Run one step on its own with `scripts/app_store_screenshots capture` (or
`export`, `frame`, `compose`). Retake a single slide with
`--only test05Alarm`; the other raw captures are kept. Re-running `compose`
alone is enough after editing a caption.

## Data

The captures show **live Puget Sound data**, so they change from run to run.
Run during the day: at night some routes stop (the Streetcar bookmark is left
out when it has no departure in the next 90 minutes), and the alarm slide is
skipped when no departure at Capitol Hill is 12 or more minutes away.

DEBUG-only launch hooks in `OBAKit/Orchestration/Application+ScreenshotSupport.swift`
put the app in the right state:

| Environment variable | Effect |
|---|---|
| `SCREENSHOT_STOP_ID` | Opens the stop's sheet over the map, as a tap on its pin does |
| `SCREENSHOT_BOOKMARKS` | Replaces all bookmarks with trip bookmarks built from live arrivals (JSON: `group`, `name`, `stopID`, `routeID`) |
| `SCREENSHOT_END_LIVE_ACTIVITIES` | Ends every Live Activity, so slide 2's is gone from the Dynamic Island over Safari |

The tests also pass these launch arguments, which override UserDefaults for
the run without changing what's stored:

- `-UserDataStore.lastSelectedView 0` starts on the Map tab, whichever tab the
  simulator was left on.
- `-com.apple.TipKit.HideAllTips 1` hides tips; a popover tip swallows the
  first tap.
- a `donationRequestDismissedDateKey` date hides the donation card on the stop
  page.

They also set the existing `TEST_SUPPRESS_ALERT_BULLETINS`.

## Slides

| # | Capture | Screen |
|---|---|---|
| 1 | `01-stop-arrivals` | Map with the Capitol Hill station sheet |
| 2 | `02-lock-screen` | Live Activity on the Lock Screen |
| 3 | `03-trip-vehicle` | Trip page with the train on the map |
| 4 | `04-trip-planner` | Trip planner results to UW's Allen Center |
| 5 | `05-alarm` | Add Reminder sheet |
| 6 | `06-bookmarks` | Bookmarks tab, Work and Home groups |
| 7 | `07-open-source` | opentransitsoftwarefoundation.org in Safari |

The Lock Screen slide presses the lock button through a private
`XCUIDevice` selector (`pressLockButton`). If a future Xcode drops it, that
test skips, and the slide has to be captured by hand: track a trip, lock the
simulator, and save the screenshot as `raw/02-lock-screen.png`.

## One-time setup

Pillow, and frames-cli with the Apple Frames 4 asset pack:

```bash
pip3 install Pillow
git clone https://github.com/viticci/frames-cli.git ~/.local/share/frames-cli
ln -s ~/.local/share/frames-cli/frames ~/.local/bin/frames   # ~/.local/bin on PATH
mkdir -p ~/.local/share/frames-assets && cd ~/.local/share/frames-assets
curl -sSL -o AppleFrames401.zip https://cdn.macstories.net/AppleFrames401.zip
unzip -q AppleFrames401.zip
frames setup ~/.local/share/frames-assets/Frames   # non-interactive; bare `frames setup` prompts
```

The caption font is `/Library/Fonts/SF-Pro-Display-Bold.otf` (from Apple's SF
Pro download); without it the script falls back to the system San Francisco
font.
