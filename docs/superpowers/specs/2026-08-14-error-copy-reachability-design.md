# Unreachable server vs bad stop data — error copy

**Date:** 2026-08-14
**Status:** Approved for implementation
**Issues:** #1281, #1276

## Goal

Riders currently see “the server appears to be down” for two different failures: the regional host is unreachable (timeout / connection / 502–504), and the host returned a body this app cannot decode. The first is often a VPN or firewall; the second is bad stop/agency data. They need distinct copy.

## Non-goals

- No new report-a-problem CTA. The issue text for #1276 asks riders to “let us know”; wiring that is a separate product change.
- No change to which HTTP status codes map to `.serverUnavailable` vs `.serverError`.
- No VPN detection. We mention VPN as one possible cause, not as a diagnosed cause.

## Classification

| Raw error | Today | After |
|---|---|---|
| Timeout / cannot connect / cannot find host / 502–504 | `.serverUnavailable` | unchanged |
| `DecodingError` with a region name | `.serverUnavailable` | **`.invalidResponseData(regionName:)`** |
| `DecodingError` with no region | `UnstructuredError` (decoding_failure) | same case, copy no longer says “server experiencing problems” |

Empty HTTP 200 stays `APIError.requestNotFound` (see #1268). Do not fold it into either of these cases.

## Copy (English)

`.serverUnavailable` — keep it short, do not claim the server *is* down:

> Unable to reach the server for {region}. {app} can't show transit information for this region right now. The server may be down, or a VPN or firewall may be blocking it.

`.invalidResponseData`:

> The server for {region} returned data this app can't read. That's usually a problem with the stop or agency feed, not with {app}. Try again shortly.

No-region decoding fallback:

> The server returned data this app can't read. That's usually a problem with the stop or agency feed. Please try again shortly.

## UI

Empty-state / error icons treat `.invalidResponseData` like other “bad payload” errors (`exclamationmark.triangle` / `bolt.horizontal.circle`), not `server.rack`. That is the visual distinction #1276 is after.

## Tests

- Existing `Classify decoding error with region name becomes server unavailable` must fail on `main` once rewritten to expect `.invalidResponseData`.
- `.serverUnavailable` description still includes the region name; it also mentions VPN.
- `.invalidResponseData` description includes the region and does not say the server is down.
- Timeout / 502–504 still classify as `.serverUnavailable`.
- Do not load stop-page views.

## Locales

Update `OBALoc` defaults and `en.lproj`. Other locales keep the previous `.serverUnavailable` wording until translated; the new key falls back to the English `value:` via `OBALoc`.
