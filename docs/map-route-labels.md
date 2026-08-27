# Map stop route labels

Stop pins on the map show a compact route list under the icon (`Stop.mapTitle`)
and the same list in the callout (`Stop.mapCalloutText`):

- Up to three short names, comma-separated, no `"Routes:"` prefix.
- Overflow is marked with a single ellipsis glyph (`…`, U+2026), e.g. `"10, 12, 49…"`.
- The marker is inside `OBALoc("formatters.map_routes_overflow_fmt")` so a
  translator can substitute a locale-conventional overflow mark.

UIKit's own tail truncation also renders `…`. Using three ASCII periods (`...`)
for the overflow hint made a pin that fit look different from one that UIKit
truncated — the inconsistency #514 reported.

`Stop.subtitle` is unchanged. Home, Recent, and Nearby list rows still show
`"Routes: 10, 12, 49"` with every route. That is not a map surface.

See also #132 (pin-label overflow hint) and #1267 (`formattedMapRoutes`).
