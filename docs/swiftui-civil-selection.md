# System civil date selection

`View.Date_picker.create` and host date/range dialogs use SwiftUI DatePicker.
The standard contract is one inclusive continuous date range. `selectable_dates`
and the Year/Month/Day menu implementation are removed. The caller audit found
only a Gallery whitelist demonstration, so no custom extension is retained.

Civil values remain Gregorian year/month/day records. The native picker explicitly
uses a Gregorian calendar and UTC; conversion uses noon and validates the exact
round trip. Locale remains inherited, so the system chooses component order.
TimePicker keeps its existing native time-only behavior.

The supported system-picker range is **1582-10-15 through 9999-12-31**. The civil
value type itself still represents years 1…9999, but picker construction and wire
validation reject earlier bounds. Foundation's Gregorian/ISO calendar converts
1582-10-10 to 1582-10-20 at its historical cutover. Silently normalizing that date
would violate date-only ownership. This is an explicit native-contract narrowing,
not an approximation or a fallback to custom menus.

Application bounds must contain the selection. Native changes are tentative until
OCaml commits them; rejection restores the authoritative date. Configuration,
handler, presentation and disposal changes invalidate stale callbacks.
