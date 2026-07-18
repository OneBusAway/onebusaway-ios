# Add-Region Deep Link & Custom Region Form Expansion — Design

**Date:** 2026-07-18
**Status:** Approved

## Goal

Allow the `onebusaway://add-region` deep link and the Add/Edit Custom Region UI to
specify three additional, optional region values that the `Region` model already
supports but that custom regions cannot currently set:

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

## Components

### 1. `URLSchemeRouter` (`OBAKitCore/DeepLinks/URLSchemeRouter.swift`)

- `AddRegionURLData` gains `sidecarURL: URL?`, `umamiURL: URL?`, `umamiID: String?`.
- `decodeAddRegion` parses `sidecar-url`, `umami-url`, `umami-id`. URLs go through
  the existing `validateAndCreateURL`; failures yield `nil` for that field.
  `umami-id` is whitespace-trimmed; blank becomes `nil`.

### 2. `Region` (`OBAKitCore/Models/Region.swift`)

- The custom-region initializer gains `sidecarBaseURL: URL? = nil` and
  `umamiAnalytics: UmamiAnalyticsConfig? = nil` parameters, assigned instead of
  hardcoded `nil`.
- `UmamiAnalyticsConfig` gains a public memberwise `init` (currently only the
  synthesized internal one exists, invisible outside OBAKitCore).

### 3. Deep link handling (`OBAKit/Orchestration/Application.swift`)

- The `.addRegion` case builds `UmamiAnalyticsConfig` only when both umami values
  are present, and passes it plus `sidecarURL` to the `Region` initializer.

### 4. `RegionCustomForm` (`OBAKit/Onboarding/RegionPicker/RegionCustomForm.swift`)

- Three new `@State` string fields in **two new sections** (Approach B):
  - **Sidecar Server** — one URL field. Footer: optional, used for OneBusAway.co
    features like alarms and surveys.
  - **Analytics** — Umami URL field + website ID field. Footer: optional; both
    fields are required to enable analytics, leave blank to disable.
- URL fields styled like Base URL (URL keyboard/content type, no
  autocapitalization/autocorrection).
- URL normalization: extract a general static `normalizeURL` helper (trim, assume
  `https://`, strip trailing slashes, require http(s) + host) shared with
  `normalizeBaseURL`; the `/api/where` stripping applies only to the base URL.
- Save applies the both-or-nothing umami rule via a small pure static helper.
- `setInitialValues` populates the new fields when editing. This also fixes a
  latent bug: editing a custom region today silently drops any existing
  sidecar/umami values because the initializer nils them.

### 5. Tests (`OBAKitTests`)

- `URLSchemeRouter` decode: all params present; none present (backward compat);
  partial umami pair; invalid URLs.
- Form helpers: `normalizeURL` cases; umami both-or-nothing helper cases.
- `Region` Codable round-trip: custom region with sidecar + umami encodes and
  decodes correctly.

### 6. Docs

- Update the deep-linking example URL in `CLAUDE.md` and README.

## Localization

New form section headers/footers use `OBALoc` with new string keys, following the
existing `custom_region_builder_controller.*` key convention.
