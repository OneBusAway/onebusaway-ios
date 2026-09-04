# Arrival vs departure at first and layover stops

At a terminal (stop sequence 0) the vehicle is *leaving*, not pulling in.
The minutes badge was just `5m` / `NOW` either way, so riders had to parse
the fine print. #447 / stop 1_13200.

## What changed

- Countdown on the stop page (chrono + grouped) grows a one-word caption:
  **Arrives** or **Departs**, from `ArrivalDeparture.arrivalDepartureStatus`.
- VoiceOver for upcoming rows uses `arrives in` vs `departs in`. Grouped
  cards use `next arrival` vs `next departure`. The old strings always
  said "departs".
- Trip cards and bookmarks do not get a caption — those surfaces are
  already one-sided.

No new Settings toggle. The model already distinguishes the two; this is
display only.

## Tests

`FormattersTests` captions. `StopPageAccessibilityCopyTests` VoiceOver verbs.
