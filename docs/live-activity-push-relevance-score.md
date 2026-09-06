# Live Activity push relevance-score (#1252)

## Problem

PR #1243 gives newly Tracked trips a monotonic on-device `relevanceScore` so
the Dynamic Island follows the newest Track. OBACloud push samples (and the
Node helper in `docs/LiveActivityPushNotifications.md`) used to send a flat
`"relevance-score": 100` on every update, which re-ties scores after a push
and undoes Island ordering.

## App vs push

| Path | Who sets the score | Preserves Track order? |
|---|---|---|
| `Activity.requestProminent` / `promoteToDynamicIsland` | App (monotonic) | Yes |
| Local arrivals refresh (`LiveActivityUpdateCoalescer`) | `contentPreservingRelevance` | Yes |
| APNs Live Activity update | Push payload | **Only if `relevance-score` is omitted or per-activity** |

The app cannot intercept APNs Live Activity content updates before ActivityKit
applies them. Fixing #1252 is a **push-side** contract; the iOS client already
does the right thing on every local refresh.

## Contract

1. Prefer **omitting** `relevance-score` on update/end payloads.
2. If set, it must be **per activity** and keep newest-Track highest.
3. Never default every card to `100`.

See the updated examples in `docs/LiveActivityPushNotifications.md`.
