# Native focus and layout services

The Swift host decodes `request_focus` (kind 6), `clear_focus` (kind 7) and
`measure_layout` (kind 14). Target identities must be positive Int64 values.
Malformed identities, truncated commands and trailing bytes reject the candidate
frame before any operation can execute.

Target resolution belongs to the requesting `BonsaiSession`. It requires the
current node, epoch, properties, bindings and children to match the presented
tree, and checks active navigation/presentation content. A removed, hidden or
speculative target returns an error. The native window must still belong to the
session's presentation owner. Existing host-request cancellation, admission,
presentation acknowledgment and session-restart fences apply.

## Focus

Focus requests operate on the existing plain, secure or multiline native text
control inside SwiftUI. Controls must be attached to the owned window and enabled
for selection. The host reports native refusal instead of claiming focus was
acquired. Non-text nodes have no input-focus resource and return an error.

Clearing focus only affects the owned window. macOS uses `makeFirstResponder`;
iOS locates the first-responder view inside that window and asks it to resign.
An already unfocused window succeeds, while native refusal returns an error.
The operation never searches another window or the application's global key
window. Text editing and composition continue to use the existing native input
controllers and their OCaml event/revision protocol.

## Layout

Each native node contributes a SwiftUI bounds anchor through
`transformAnchorPreference`, preserving descendants' anchors and native layout
traits. An overlay at the application root resolves the anchors into logical
points relative to application content. No sizing view, bitmap export or OCaml
update is introduced around individual nodes. A root-local attachment owns the
latest samples; missing anchors and root disappearance clear only that
attachment's records. These records are not observable state.

Measurement returns four little-endian Float64 values: left, top, width and
height. Values must be finite and extents nonnegative. A missing mounted sample
returns an error. Moving the window on screen does not change these content
coordinates. The response uses the existing actual OCaml `layout` decoder.

## Evidence and remaining work

The actual OCaml fixture receives test-owned target identities through its
application event channel, issues the public host request and renders the
decoded response. Tests mount its real SwiftUI tree in a native window and
verify plain/secure/multiline focus, disabled and removed targets, another
window's unchanged first responder, presentation deferral, window detachment,
120-by-40-point geometry and screen-position independence. These are native
control and layout tests, not a mock host-effect implementation.

Scroll-to remains unfinished: its existing contract is a normalized container
offset and requires integration with the SwiftUI scroll controllers. Physical
iOS focus/IME, detached presentation surfaces, toolbar geometry and complete
visual/performance acceptance remain unverified. The target APIs still take
renderer node identities; this checkpoint does not add an application reference
API or claim all widget-family behavior has been accepted.

The first full regression exposed 22 layout assertion failures when sampling
was implemented with a per-node stateful modifier. That approach was removed.
The anchor implementation passes 35 related tests in seven suites, including
native-reference raster parity for Spacer, Divider, layout priority, weighted
stacks and actual OCaml updates, alongside native focus and measurement.
See `/tmp/swiftui-node-services-full.log` for the failed broad gate and
`/tmp/swiftui-node-services-anchors-green.log` for the corrected focused gate.

The corrected full run passes all 409 Swift tests in 90 suites in 319.794 seconds
(`/tmp/swiftui-node-services-full-final.log`). The complete iOS 18 module and
ten Swift App entrypoints compile, with Simulator and Intel explicitly rejected.
Host Effects' independent App window passes Clear focus and the existing native
service scenarios in 32.278 seconds with root anchor sampling
(`/tmp/swiftui-node-services-window-final.log`). These checks do not close the
physical-device and presentation-surface acceptance gaps listed above.
