# Civil Date and Time Selection

`View.Date_picker.create` and `View.Time_picker.create` replace the Material
calendar and dial constructors. Their independent native nodes are decoded,
validated and rendered by SwiftUI. Gallery includes controlled selection,
rejection, restricted dates, disabling and handler replacement.

## Public values and controls

`View.Date.create ~year ~month ~day` constructs a proleptic Gregorian date.
Years are 1 through 9999, month lengths follow Gregorian leap-year rules, and
historical dates such as 1582-10-10 remain valid. The private immutable record
exposes components for application state and formatting. Date values never pass
through Foundation Calendar, a time zone or an application timestamp.

`View.Date_picker.create` takes a selected date, inclusive first/last bounds and
an optional list of selectable dates. It rejects reversed bounds, out-of-range
values and a selected date absent from a nonempty selectable list. It sorts and
deduplicates the list, rejecting inputs above 65535 entries. An empty list means
the full bounded interval. The label defaults to `Date` and cannot be blank.

`View.Time.create ~hour ~minute` constructs a time with hour 0 through 23 and
minute 0 through 59. `View.Time_picker.create` takes this value and a format:
`System` (default), `Hour_12` or `Hour_24`. The label defaults to `Time` and cannot
be blank. Both controls support stable keys and an enabled flag. Disabled
controls have no change binding. The old Material constructors and their civil
event hooks were removed, with no aliases.

## Native presentation

The date control uses linked native SwiftUI menu Pickers for year, month and day.
`CivilDateDomain` supplies only selectable components and indexes restricted
dates once. An unrestricted interval enumerates years and only the month/day
choices requested, rather than expanding every date. Changing year or month
preserves existing fields when possible; otherwise it selects the nearest
available month/day, with earlier values winning ties. A direct unavailable
component is rejected. For example, changing 2024-02-29 to 2025 selects February
28, while an upper bound of 2025-03-10 clamps a subsequent March choice to day 10.

Apple's [DatePicker](https://developer.apple.com/documentation/swiftui/datepicker)
binds a Foundation Date and supports ranges. A local Foundation conversion probe
found that both Gregorian and ISO8601 Calendar convert 1582-10-10 to 1582-10-20.
They also accept 1500-02-29 under their historical calendar behavior, whereas the
civil contract rejects that Gregorian century leap day. Linked component Pickers
preserve the full date domain without private calendar APIs or OS corrections.
Run `swift tool/probe_foundation_civil_calendar.swift` to repeat the observation.

The time control uses native SwiftUI DatePicker in hour/minute mode with an
explicit UTC environment. A fixed reference day carries wall-clock fields; it
is not an application timestamp. Conversion handles day rollover, rejects
non-finite dates and preserves midnight/noon distinctions. An explicit hour-cycle
override preserves the user's language, region, numbering system and calendar
metadata. Native macOS acceptance verifies that the underlying time control uses
UTC and that its action updates the actual OCaml state.

Material's current-day marker, initial calendar day/year page and time dial
presentation are removed. The date control always exposes year selection.

## Wire and controlled input

Nodes 59 and 60 are `date_picker` and `time_picker`. Date properties encode the
selected date, bounds, a UInt16 count of selectable dates, label and enabled flag.
Time properties encode the selected time, format, label and enabled flag. The
full property masks are 63 and 15. Wire dates use UInt16 year and UInt8 month/day;
times use UInt8 hour/minute. Both codecs validate values and configuration.
The wire selectable-date list must already be strictly ascending and unique.
Malformed properties, unexpected children or incorrect bindings cannot stage.

Event tags 46 and 47 carry date and time respectively. The sequence, epoch,
revision, node and handler envelope still applies. Consecutive requests coalesce
only within the same event kind and binding; invalid values do not mutate the
queue. A controller immediately displays an admitted selection, keeps the final
pending request across earlier echoes, and restores OCaml's selected value when
the matching request finishes. An unchanged response can reject a request and
must still restore the native selection.

Session admission requires the current node and displayed epoch, matching
presented configuration and handler, an enabled control, an admissible value and
active visible content. Date/time events cannot cross control kinds. Configuration
changes, handler replacement, rejected requests and disposal invalidate stale
native bindings. Replacing a handler also clears its pending local selection.
The session resolves requests after pumping the actual runtime, including
responses that contain no new frame.

## Verification and remaining acceptance

Tests cover all 1440 clock minutes, historical and boundary dates, leap rules,
partial months, restricted choices, clamping, invalid integers, noncanonical and
oversized lists, UTC conversion and locale-preserving hour cycles. OCaml protocol
round trips cover new nodes and updates. Those round trips exposed reversed
field reads in the shared civil readers; explicit sequential reads now preserve
the wire order.

`native-civil-events` sends seven exact date/time values to real OCaml handlers
and checks replay rejection. It now produces the independent native nodes.
`native-civil-picker` embeds the actual Gallery component. Tests cover accepted
and ignored requests, repeated no-diff rejection, pending presentation, disabled
and hidden controls, restricted dates, handler replacement and disposal. A real
NSHostingView window exercises a SwiftUI year menu item's action and the native
time control's action, then checks the resulting OCaml selections. These are
application-local native actions, not physical-device interaction evidence.

Full visual acceptance, accessibility usability, the large-year-menu performance
budget and physical iOS interaction remain outstanding. No date/time test
satisfies the Mail screenshot requirement. The supported targets remain physical
iOS 18+ arm64 and macOS 26+ arm64; Simulator is unsupported.

## Modal civil selection

[Host picker services](swiftui-host-pickers.md) reuse the civil date domain and
UTC clock conversion for asynchronous date, date-range and time sheets. Widget
selection remains controlled through on_select/on_changed events; the modal
services instead keep a draft and return an optional result on Save or Cancel.
Both paths preserve proleptic Gregorian values and native locale hour cycles.
