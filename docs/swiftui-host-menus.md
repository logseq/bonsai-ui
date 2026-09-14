# SwiftUI action menu service

`Host_effect.show_native_menu` presents an asynchronous action chooser in the
owned application window. The host uses a SwiftUI sheet containing a scrollable
List of native Buttons and a Cancel button. Inline and hierarchical menus use
`View.Menu`; this service provides a modal choice with a typed asynchronous result.

## Domain and wire contract

BSFR request kind 11 contains a UInt16 item count, then each item's
UInt32-length UTF-8 ID, UInt32-length UTF-8 label and Boolean enabled flag.
The entire candidate frame validates before presentation or native execution.

- The count is 1 through 1024. Disabled items remain visible, including when
  every item is disabled; Cancel remains available.
- IDs are nonempty, unique byte strings. Canonically equivalent Unicode strings
  with different UTF-8 bytes remain different identities. SwiftUI List identity
  and callback admission use those bytes as well.
- Labels must be nonblank and fit the 1 MiB string budget. IDs fit 1 MiB minus
  five bytes so their optional-string response fits the host response budget.
- OCaml rejects invalid public arguments with `Invalid_argument`. Its binary
  encoder/decoder and Swift's decoder apply the same domain constraints.
- Selection returns `Ok (Some item_id)`. Success encodes a one-byte presence
  flag, followed by a UInt32 UTF-8 length and exact ID bytes. Native dismissal or
  Cancel returns `Ok None`, encoded as a zero presence byte.

## Presentation and lifetime

Host commands start only after their frame is acknowledged and the application
is active and visible. Requests deferred before presentation wait for activation.
An already-open chooser is ephemeral: losing active or visible window ownership
cancels it, rather than reopening it on resume.

Menus and [civil pickers](swiftui-host-pickers.md) share `NativeHostDialogs`.
One chooser owns the modal slot until native dismissal completes. A concurrent
menu, civil-picker or file-dialog request fails explicitly without replacing the first one.
An existing native or declarative modal also prevents a new chooser. The sheet
blocks background OCaml input, focus, gestures, native extensions and scroll
commands. Notification action admission and timeout accounting pause during it.

Request cancellation returns `Error Cancelled`; closing or replacing the native
window also cancels pending work. Request and presenter UUIDs reject retained
buttons and old dismissal callbacks after cancellation, close and restart.
A request cancelled before native appearance completes immediately, since that
unmounted sheet cannot supply a native dismissal callback.

The preferred sheet is 320 by 320 points, with bounded sizing and a scrollable
list. Cancel carries the native cancel keyboard shortcut. The macOS tests cover
both 640- and 360-point parent windows and an actual 128-item native scroll view.

## Example and verification

Host Effects exposes `Choose action`, with Open item, Duplicate item and a
visible disabled action. Its OCaml model renders the selected ID in the separate
`Action:` status. The standalone native window scenario presses the actual
chooser and waits for `Action: duplicate`.

The Swift runtime tests link the OCaml fixture and exercise actual application
events and native accessibility Button actions, rather than substituting a
response provider. They cover Unicode IDs, disabled items, compact layout,
scrolling, dismissal, cancellation, modal contention, background admission,
inactive deferral, hidden windows, and stale callbacks across restart.
Malformed commands and response-size boundaries have additional decoder checks.

```sh
opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt @install
swift test --scratch-path _build/swift --no-parallel --filter 'hostMenus|HostMenuWireTests'
python3 native/test/test_host_effects_window.py
python3 tool/test_swift_platforms.py
```

Physical-iOS interaction, VoiceOver, touch dismissal and screenshots remain
unverified. An iOS module build does not establish that acceptance. No Simulator
support or Flutter presentation path is involved.

## Regression checkpoint

The full serial Swift regression passes **462 tests in 101 suites** in
469.588 seconds (`/tmp/swiftui-menu-full.log`). The runner verifies a fresh,
complete Swift Testing xUnit report, in addition to successful process exit.
OCaml `@all @runtest @fmt @install` passes after the public and codec changes
(`/tmp/swiftui-menu-ocaml-complete.log`). These results include the action-menu,
file-dialog contention and Unicode-ID scenarios. Physical acceptance remains open.

The standalone Host Effects window scenario passes in 40.996 seconds, selecting
Duplicate item through the SwiftUI List and observing `Action: duplicate` from
OCaml. Platform checks pass in 22.264 seconds: the iOS 18 arm64 module emits,
all eleven example entrypoints typecheck, and unsupported targets reject.
Host Effects and Mail macOS Debug Apps rebuild and verify. Their source and
binary hashes are recorded in `_build/validation/swiftui-host-menus.json`.
