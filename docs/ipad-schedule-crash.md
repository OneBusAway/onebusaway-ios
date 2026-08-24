# iPad schedule crash

Opening the Link light-rail timetable crashed on iPadOS 18 (#908). Two
causes stacked:

1. A SwiftUI `DatePicker` hosted in a `.pageSheet` `UIHostingController`
   pops a compact calendar that iPadOS 18 cannot attach. Phone stays
   `.pageSheet`; iPad uses `.formSheet`. The picker is explicitly
   `.compact` so it does not expand into a graphical calendar in the
   sheet.
2. `.task(id: selectedDate)` cancels the in-flight fetch when the date
   changes or the sheet dismisses. Applying the response after cancel
   republished into a view that was going away.

Tests cover the presentation style only. They do not load the hosting
controller's `view`.
