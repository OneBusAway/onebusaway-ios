# Region timezone display

Stop and trip clock times are the region's times, not the phone's.

A rider in Taipei looking at Puget Sound used to see 4:00 PM when the bus
leaves at noon Pacific. #332 asks for Pacific noon, with a short zone badge
only when the phone's offset differs.

## What we do not do

PR #1102 appended `TimeZone.NameStyle.shortGeneric`. That style is `PT` /
`ET` in North America and a long localized name everywhere else
(`Poland Time`, `United Kingdom Time`) on every arrival row. Aaron closed
that PR for that reason. This code never uses `.shortGeneric`.

There is no "use my local time" toggle. The issue mentioned one as a maybe;
a setting that fights the clock on every row is worse than a badge.

## Badge

`TimeZone.scheduleBadge(at:versus:)`:

1. Same GMT offset as the device → `nil` (no badge).
2. Else a 2–5 letter abbreviation (`PST`, `PDT`, `CET`, `CEST`, `JST`).
3. Else `GMT+5:30` / `GMT-8`.

`Formatters.formattedClockTime` applies that to `timeFormatter`.

## Where the zone comes from

Agency IANA identifiers (`America/Los_Angeles`) via
`agencies-with-coverage`. `CoreApplication` takes the most common
identifier in the region. Invalid strings are skipped. Until that call
returns, formatters stay on the device zone so first paint is not UTC-by-
accident.

## Tests

`TimeZoneScheduleBadgeTests` pins a January 2024 instant so DST cannot
change `PST` vs `PDT`. Warsaw must not contain "Poland" or "Time".
