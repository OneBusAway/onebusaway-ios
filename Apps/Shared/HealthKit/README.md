# Apple Health integration

Reads walking and cycling speed from Apple Health for walk-time estimates. **Off by
default.** App Review rejected it for 26.4 under guideline 2.5.1: "the app does not
appear to include any primary features that require health or fitness data."

Nothing here reaches a build unless `Apps/Shared/healthkit.yml` is included. Apple's
notice asked for every reference to go, so OBAKit has none: it sees a neutral
`SpeedSyncConfiguration` (`OBAKit/TripPlanning/SpeedSync.swift`) and the app supplies
it through `AppConfig.speedSync`. Keep it that way. Do not add `import HealthKit`, or
a string naming Health, to OBAKit or OBAKitCore.

| Lives here | Why |
|---|---|
| `Sources/*.swift` | The only code that imports HealthKit. Compiled into the app target. |
| `Sources/<locale>.lproj/HealthKit.strings` | The Settings copy. Hand-maintained; `scripts/extract_strings` does not read it. |
| `InfoPlistStrings/<App>/<locale>.strings` | Translated purpose strings, parked. Not in any target (see below). |
| `../healthkit.yml` | The entitlement, the English purpose strings, the sources, and `OBA_HEALTHKIT`. |

## Turning it back on

1. Generate with the flag. CI and Fastlane call `scripts/generate_project`, so add it
   there too:

   ```bash
   scripts/generate_project OneBusAway --healthkit
   ```

2. Restore the translated purpose strings, for that app only. `InfoPlist.strings`
   cannot be split across files, so these have to go back into the app's own tables.
   Without this step the permission sheet is in English in every locale. Safe to run
   twice:

   ```bash
   app=OneBusAway
   for f in Apps/Shared/HealthKit/InfoPlistStrings/$app/*.strings; do
     table="Apps/$app/$(basename "$f" .strings).lproj/InfoPlist.strings"
     grep -q NSHealthShareUsageDescription "$table" || cat "$f" >> "$table"
   done
   ```

   These tables are tracked and every build uses them, so never leave the keys in an
   app that is generated without the flag. They are what App Review told us to remove.

3. Check that the App ID still has the HealthKit capability and that the provisioning
   profile includes it.

4. Say so in the App Store description. Guideline 2.5.1 requires it, and the 26.4
   listing did not.

Riders who synced before the integration was removed were moved to `.manual`
(`Application.retireSyncedSpeedsIfUnsupported`), so they need to turn the switch on
again. Walking snapped to the nearest preset; bike kept its last speed.
