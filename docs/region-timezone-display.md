# Region timezone display

Opt-in setting (default **off**): stop and trip clock times can use the
region's zone instead of the phone's.

A rider in Taipei looking at Puget Sound used to see 4:00 PM when the bus
leaves at noon Pacific. #332 asks for Pacific noon, with a short zone badge
only when the phone's offset differs. Aaron required this to be opt-in
(same ask that blocked #1102 from shipping default-on).

## Settings

**Settings → Arrival & Departure Display → "Show times in region time zone"**

- Off (default): clocks use `TimeZone.current`; no region badge.
- On: clocks use the region's dominant agency IANA zone from
  `agencies-with-coverage`, with a short badge when the phone offset differs.

## What we do not do

PR #1102 appended `TimeZone.NameStyle.shortGeneric`. That style is `PT` /
`ET` in North America and a long localized name everywhere else
(`Poland Time`, `United Kingdom Time`) on every arrival row. Aaron closed
that PR for that reason. This code never uses `.shortGeneric`.

## Badge

`TimeZone.scheduleBadge(at:versus:)`:

1. Same GMT offset as the device → `nil` (no badge).
2. Else a 2–5 letter abbreviation (`PST`, `PDT`, `CET`, `CEST`, `JST`).
3. Else `GMT+5:30` / `GMT-8`.

`Formatters.formattedClockTime` applies that to `timeFormatter`.

## Where the zone comes from

Agency IANA identifiers (`America/Los_Angeles`) via
`agencies-with-coverage`. `CoreApplication` takes the most common
identifier in the region when the setting is on. Invalid strings are
skipped. Until that call returns, formatters stay on the device zone so
first paint is not UTC-by-accident. When the zone lands,
`Notification.Name.formattersTimeZoneDidChange` triggers a redraw of
on-screen clocks (and the badge).

Route timetable `Date`s are synthesized with a `Calendar` pinned to the
same `formatters.timeZone` used for formatting, so agency-local
seconds-since-midnight stay on the agency clock.

## Tests

`TimeZoneScheduleBadgeTests` pins a January 2024 instant so DST cannot
change `PST` vs `PDT`. Warsaw must not contain "Poland" or "Time". A
non-GMT device/region pair asserts the timetable clock stays agency-local.
