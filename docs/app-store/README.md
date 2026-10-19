# App Store screenshots

Everything needed to regenerate the App Store screenshot slides from the
simulator. The slide list and captions are in `screenshots.json`; the listing
text (description, keywords, promotional text) is in `listing.md`.

## Generating the screenshots

1. Do the [one-time setup](#one-time-setup) below (Pillow and frames-cli).
2. From the repo root, generate the project:

   ```bash
   scripts/generate_project OneBusAway
   ```

3. Run the pipeline. The first run takes about ten minutes, most of it the
   build; later runs take about three:

   ```bash
   scripts/app_store_screenshots
   ```

4. Check the slides in `build/app-store-screenshots/slides/`: one PNG per
   slide, numbered in App Store order, at 1206 × 2622 (the 6.3" iPhone size).
5. Drag them into App Store Connect, in order, under the matching display
   size.

To make the iPhone, iPhone Duo and Apple Watch sets in one run, use
`scripts/app_store_screenshots --all-sets`. The Duo part
[needs a click from you](#iphone-duo) partway through.

Run it in the daytime, Pacific time; see [Data](#data). A slide that fails
or skips prints a warning, and the run keeps the others. Retake it on its own:

```bash
scripts/app_store_screenshots --only test05Alarm
```

Options:

| Option | Effect |
|---|---|
| `--size 1320x2868` | Composes at the 6.9" size instead; the layout scales with the canvas |
| `--only <test>` | Runs one slide's test (`test01StopArrivals` … `test07OpenSource`); other captures are kept |
| `capture`, `export`, `frame`, `compose` | Runs one step. After editing a caption, `compose` alone is enough |
| `--duo` | Makes the [iPhone Duo](#iphone-duo) set instead |
| `--watch` | Makes the [Apple Watch](#apple-watch) set instead |
| `--all-sets` | Makes all three sets in one run: iPhone, Duo, then watch, each at its default size. It takes a step (`--all-sets compose`) but not `--size`, `--only` or `SCREENSHOT_UDID` |
| `SCREENSHOT_UDID=<udid>` | Uses that simulator instead of the newest iPhone Pro (or Duo) |

To change a caption, edit `screenshots.json` and rerun `compose`. To change
what a slide shows, edit its test in `OBAKitUITests/AppStoreScreenshotUITests.swift`.

## iPhone Duo

The Duo has its own set: landscape slides, at 2853 × 2007, of the open Duo,
plus one slide of two folded Duos showing the cover screen. Its slide list
and captions are in `duo-screenshots.json`.

```bash
scripts/app_store_screenshots --duo
```

The slides land in `build/app-store-screenshots/duo/slides/`. Upload them to
the iPhone Duo display size in App Store Connect. App Store Connect also
takes 2034 × 1398 (`--size 2034x1398`), and either size in portrait.

The run needs you once or twice. Nothing scriptable folds or unfolds the
simulator: `simctl` and XCUITest have no posture API, and Device Hub's
buttons aren't reachable through Accessibility. So the script captures in
whichever posture the Duo is already in, then asks for the other one and
waits:

- **Open:** in Device Hub, click the rightmost posture button under the
  device (flat). The open slides are captured.
- **Folded:** click the posture button just right of the divider. The
  cover-screen captures are taken.

There's no Lock Screen slide in the Duo set: `pressLockButton` doesn't lock
the Duo, so that test skips there.

It tells the postures apart by whether the inner display is lit
(`scripts/app_store/duo_posture.py`). Device Hub
(`Xcode.app/Contents/Applications/DeviceHub.app`) is the simulator app from
Xcode 27 on. An older `Simulator.app` can still show the Duo, but it has no
posture buttons, so the Duo stays folded.

How the Duo set differs from the iPhone set:

- **Capture.** It uses the same tests. The script decides which tests run
  in which posture and passes the posture in (`SCREENSHOT_POSTURE`). Open,
  the test captures the inner display, since `XCUIScreen.main` is the cover
  one. Folded, the capture gets a `-folded` suffix
  (`01-stop-arrivals-folded`).
- **Frame.** There's no frames-cli step, since frames-cli has no Duo frame.
- **Compose.** `scripts/app_store/compose_duo_screenshots.py` draws the Duo
  itself, open or folded, around each capture, with the screen corner radii
  from the simulator's device profile. A slide lists one capture or more under
  `devices`.

`--only` works with `--duo` too. It runs that test only in the postures that
use it.

## Apple Watch

```bash
scripts/app_store_screenshots --watch
```

The run captures four screens of the watch app into
`build/app-store-screenshots/watch/`: the bookmarks list, Nearby, a route, and
a stop. They come from the newest Apple Watch Ultra simulator, which
`scripts/resolve_watch_simulator_udid --ultra` creates if there isn't one.
They're 422 × 514, the Ultra's screen size and one of the sizes App Store
Connect takes for the watch, and they're uploaded as they are, with no frame
or caption. `--only 03-route` retakes one.
It builds the `WatchApp` scheme, so the project must be generated without
`--no-watch`.

The watch has no UI test target, so `scripts/app_store/capture_watch_screenshots.py`
drives the app directly. It sets the simulated location to Capitol Hill, then
for each slide in `watch-screenshots.json`:

1. Relaunches the app with that slide's launch environment.
2. Waits 15 seconds for live data.
3. Saves a screenshot.

DEBUG-only hooks in `OBAKitWatch/ScreenshotHooks.swift` read the environment:

| Environment variable | Effect |
|---|---|
| `TEST_SCREENSHOT_TAB` | `nearby` opens on the Nearby tab |
| `TEST_SCREENSHOT_BOOKMARKS` | Replaces the bookmarks synced from the phone with trip bookmarks built from live arrivals. It uses the same JSON as on iOS; the slide config's `bookmarks` list fills it in |
| `TEST_SCREENSHOT_STOP_ID` | Opens that stop's arrivals |
| `TEST_SCREENSHOT_ROUTE_ID` | Opens that route's Nearby card once it loads, on the Nearby tab |

`simctl status_bar` doesn't work on watchOS, so the watch clock shows the real
time, not 9:41.

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

## Data

The captures show **live Puget Sound data**, so they change from run to run.
Run during the day: at night some routes stop (the Streetcar bookmark is left
out when it has no departure in the next 90 minutes), and the alarm slide is
skipped when no departure at Capitol Hill is 12 or more minutes away.

DEBUG-only launch hooks in `OBAKit/Orchestration/Application+ScreenshotSupport.swift`
put the app in the right state:

| Environment variable | Effect |
|---|---|
| `TEST_SCREENSHOT_STOP_ID` | Opens the stop's sheet over the map, as a tap on its pin does. Classic map only; the experimental map panel ignores it |
| `TEST_SCREENSHOT_BOOKMARKS` | Replaces all bookmarks with trip bookmarks built from live arrivals (JSON: `group`, `name`, `stopID`, `routeID`) |
| `TEST_SCREENSHOT_END_LIVE_ACTIVITIES` | Ends every Live Activity. Every test sets it, so slide 2's is gone from the Dynamic Island over Safari and retakes of slide 2 don't stack activities |

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
