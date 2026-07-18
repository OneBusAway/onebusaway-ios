# Add-Region Deep Link & Custom Region Form Expansion — Design

**Date:** 2026-07-18
**Status:** Approved

## Goal

Allow the `onebusaway://add-region` deep link and the Add/Edit Custom Region UI to
specify additional optional region values (three query parameters mapping onto two
`Region` model fields) that the model already supports but that custom regions
cannot currently set:

- **Obaco sidecar server URL** (`Region.sidecarBaseURL`)
- **Umami analytics URL + website ID** (`Region.umamiAnalytics: UmamiAnalyticsConfig`)

## Deep Link Format

New optional query parameters, alongside the existing `name`, `oba-url`, and `otp-url`:

```
onebusaway://add-region?name=REGION_NAME
    &oba-url=ENCODED_OBA_URL
    &otp-url=ENCODED_OTP_URL
    &sidecar-url=ENCODED_OBACO_URL
    &umami-url=ENCODED_UMAMI_URL
    &umami-id=UMAMI_WEBSITE_ID
```

Naming follows the Region model's internal naming (`sidecarBaseURL`,
`UmamiAnalyticsConfig`) rather than the regions.json feed keys.

## Rules

1. **All three new values are optional.** Their absence changes nothing about
   existing behavior.
2. **Umami is both-or-nothing.** A `UmamiAnalyticsConfig` is constructed only when
   both a valid `umami-url` and a non-blank `umami-id` are present. A partial pair
   is silently ignored (`umamiAnalytics = nil`); the region is still added/saved.
   This applies identically to the deep link and the form.
3. **Well-formed-only validation.** New URL fields get syntactic validation and
   normalization only. No network reachability checks — only the OBA base URL keeps
   its existing live server validation. Invalid optional URLs degrade to `nil`,
   matching the current `otp-url` posture. The only hard failure remains a bad
   `oba-url`.
4. **Nested URLs must be percent-encoded.** `URLComponents` percent-decodes query
   item values and splits on unencoded `&`, so an unencoded
   `sidecar-url=https://x.co/api?a=1&b=2` truncates at `&b`. Deep links are
   machine-authored; document the encoding requirement rather than trying to
   recover from unencoded input.
5. **Deep link URLs require an explicit scheme; the form assumes `https://`.**
   The router's `validateAndCreateURL` rejects scheme-less strings; the form's
   normalization assumes `https://` for human-typed input. This split matches the
   existing `oba-url`/`otp-url` behavior and is deliberate: machine-authored links
   carry full percent-encoded URLs, humans type hostnames.

## Components

### 1. `URLSchemeRouter` (`OBAKitCore/DeepLinks/URLSchemeRouter.swift`)

- `AddRegionURLData` gains `sidecarURL: URL?`, `umamiURL: URL?`, `umamiID: String?`,
  plus a computed `umamiAnalytics: UmamiAnalyticsConfig?` that applies the
  both-or-nothing rule via the shared failable init (see §2). Consumers must use
  the computed property — `umamiID != nil` alone does not mean analytics is
  enabled (an invalid `umami-url` can leave a dangling ID).
- `decodeAddRegion` parses `sidecar-url`, `umami-url`, `umami-id`. URLs go through
  the existing `validateAndCreateURL`; failures yield `nil` for that field.
  `umami-id` is whitespace-trimmed; blank becomes `nil`.

### 2. `Region` (`OBAKitCore/Models/Region.swift`)

- The custom-region initializer gains `sidecarBaseURL: URL? = nil` and
  `umamiAnalytics: UmamiAnalyticsConfig? = nil` parameters, assigned instead of
  hardcoded `nil`.
- `UmamiAnalyticsConfig` gains a public memberwise `init` (currently only the
  synthesized internal one exists, invisible outside OBAKitCore) **and** a public
  failable `init?(url: URL?, id: String?)` that returns `nil` unless `url` is
  present and `id` (whitespace-trimmed) is non-blank. This failable init is the
  single source of truth for the both-or-nothing rule; `AddRegionURLData` and the
  form both call it rather than re-implementing the check.

### 3. Deep link handling (`OBAKit/Orchestration/Application.swift`)

- The `.addRegion` case passes `regionData.sidecarURL` and
  `regionData.umamiAnalytics` (the computed property from §1) to the `Region`
  initializer. No rule logic lives here.

### 4. `RegionCustomForm` (`OBAKit/Onboarding/RegionPicker/RegionCustomForm.swift`)

- Three new `@State` string fields in **two new sections** (Approach B):
  - **Sidecar Server** — one URL field. Footer: optional, used for OneBusAway.co
    features like alarms and surveys.
  - **Analytics** — Umami URL field + website ID field. Footer: optional; both
    fields are required to enable analytics, leave blank to disable.
- URL fields styled like Base URL (URL keyboard/content type, no
  autocapitalization/autocorrection). The website ID field is a UUID: disable
  autocapitalization and autocorrection, but do **not** set the URL content type
  or keyboard.
- URL normalization: extract a general static `normalizeURL` helper (trim, assume
  `https://`, strip trailing slashes, require http(s) + host) shared with
  `normalizeBaseURL`; the `/api/where` stripping applies only to the base URL.
- Save applies the both-or-nothing umami rule via
  `UmamiAnalyticsConfig.init?(url:id:)` (§2) — no duplicate rule logic in the form.
- `setInitialValues` populates the new fields when editing. This **must land in
  the same change** as the new initializer parameters: once the fields become
  settable (e.g. via deep link), an edit pass that didn't repopulate them would
  silently drop them on save. (No such bug exists today, because nothing can set
  these fields on a custom region yet.)

### 5. Tests (`OBAKitTests`)

- `URLSchemeRouter` decode: all params present; none present (backward compat);
  partial umami pair; invalid URLs.
- At least one decode test built from a **raw URL string** (not
  `URLComponents.queryItems`, which auto-encodes and therefore can't exercise
  encoding bugs) with a percent-encoded nested URL, plus one demonstrating that an
  unencoded `&` truncates the nested URL — locking in the documented behavior.
- `AddRegionURLData.umamiAnalytics` / `UmamiAnalyticsConfig.init?(url:id:)`:
  both present → config; either missing/blank → nil (covers the partial-umami
  collapse independent of Application).
- Form helpers: `normalizeURL` cases.
- `Region` Codable round-trip: custom region with sidecar + umami encodes and
  decodes correctly. Add a `Fixtures` variant (alongside
  `customMinneapolisRegion`) that sets both fields.

### 6. Docs

- Update the deep-linking example URL in `CLAUDE.md` and README.

## Localization

New form section headers/footers use `OBALoc` with new string keys, following the
existing `custom_region_builder_controller.*` key convention.
