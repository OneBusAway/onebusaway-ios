# Map stop route labels

Stop pins on the map show a compact route list under the icon (`Stop.mapTitle`)
and the same list in the callout (`Stop.mapCalloutText`):

- Up to three short names, comma-separated, no `"Routes:"` prefix.
- Overflow is marked with a single ellipsis glyph (`…`, U+2026), e.g. `"10, 12, 49…"`.
- The marker is inside `OBALoc("formatters.map_routes_overflow_fmt")` (all 13
  OBAKitCore catalogs). zh-Hans / zh-Hant use `……`.

UIKit's own tail truncation also renders `…`. Using three ASCII periods (`...`)
for the overflow hint made a pin that fit look different from one that UIKit
truncated — the inconsistency #514 reported.

**Bookmark pins** are different: the title is `bookmark.name`, not the route
list, so truncating the callout would hide routes with no pin/callout consistency
win. They use `Stop.bookmarkCalloutText` (same compact style, `limit: .max`).

`Stop.subtitle` is unchanged. Home, Recent, and Nearby list rows still show
`"Routes: 10, 12, 49"` with every route. That is not a map surface.

See also #132 (pin-label overflow hint), #1267 (`formattedMapRoutes`), #1342.
