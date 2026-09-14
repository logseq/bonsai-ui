# Expandable Message Composer

## Problem

`Native_widget.Message_composer` starts as an editor and owns only its focused
and multiline presentation. A consumer needs progressive disclosure from a real
Material extended floating action button into a focused modal composer, with
draft, focus timing, dismissal, and inactive accessibility layers kept inside
one Flutter `State`.

Expressing presentation in OCaml would add a frame round trip at the interaction
boundary and split ownership of uncontrolled editor resources. The logical
protocol also does not own Flutter Navigator routes, keyboard insets, modal
semantics, or renderer resources needed by arbitrary native-widget children.

## Decision

The framework exposes public
`Bonsai_flutter_ui.Native_widget.Expandable_message_composer` and public Dart
`ExpandableMessageComposer` support as built-in native widget kind `7`, schema
version `1`. The native node has `Stateful` and `Semantics` capabilities. Child
zero is the extended-FAB icon. Remaining children correspond one-for-one and in
order with encoded composer button metadata. Both OCaml construction and Dart
registration enforce the count and ordering contract.

The OCaml module owns application enablement and event handling but exposes no
application-controlled presented property. It provides leading/trailing button
values with `Always`, `When_empty`, and `When_non_empty` visibility,
plain/filled styles, per-button enablement, `Text_changed`, `Button_pressed`,
`button`, `create`, `create_with_handler`, `event_of_payload`, stable event IDs
`1` and `2`, and `For_testing.decode_props_exn`.

`create` accepts an optional key, enabled state, non-empty visible FAB label,
non-empty FAB tooltip, FAB icon child, animation duration,
`Animation.Curve.t`, maximum editor lines, hint text, buttons, and an event
callback. Defaults are 200 milliseconds, `Animation.Curve.Ease_out`, five
lines, and `"Ask anything"`. Duration zero is the reduced-motion contract.

All strings must be valid UTF-8. FAB label, FAB tooltip, and button tooltips must
be non-empty. Animation duration is in `0..65535`, maximum lines in `1..65535`,
button count in `0..65534` so the total child count fits `uint16`, and every
button ID is unique and in `1..4294967295`. OCaml rejects invalid public values;
Dart repeats all wire-boundary validation.

### Version-1 property payload

All integers are unsigned little-endian. Strings are raw UTF-8 bytes without a
terminator. The fixed header is 24 bytes:

| Offset | Width | Meaning |
| ---: | ---: | --- |
| 0 | 1 | flags: bit 0 is `enabled`; all other bits are reserved zero |
| 1 | 1 | curve: `0` linear, `1` ease-in, `2` ease-out, `3` ease-in-out |
| 2 | 2 | animation duration in milliseconds |
| 4 | 2 | positive `max_lines` |
| 6 | 2 | composer button count |
| 8 | 4 | FAB label byte length |
| 12 | 4 | FAB tooltip byte length |
| 16 | 4 | hint byte length |
| 20 | 4 | reserved zero |

The header is followed by FAB label bytes, FAB tooltip bytes, and hint bytes.
Each button then uses the existing 12-byte metadata header followed by tooltip
bytes: `uint32 id`; one-byte position (`0` leading, `1` trailing); one-byte
visibility (`0` always, `1` when empty, `2` when non-empty); one-byte style
(`0` plain, `1` filled); one-byte flags (bit 0 enabled, remaining bits reserved
zero); `uint32 tooltip_length`; tooltip bytes. Decoders reject invalid enums,
reserved bits or bytes, zero or duplicate IDs, empty required strings, invalid
UTF-8, lengths beyond the payload, truncation, and trailing bytes.

Event `1` contains only raw UTF-8 editor bytes. Event `2` contains a positive
`uint32` button ID followed by raw UTF-8 editor bytes. Event decoding consumes
the complete event payload, preserves whitespace and Unicode exactly, and
filters wrong kinds, versions, event IDs, and malformed bytes.

### Flutter ownership and modal route

One `_ExpandableMessageComposerState` owns a `TextEditingController`,
`FocusNode`, one `ModalBottomSheetRoute`, and a monotonically increasing route
generation. A FAB press pushes the route locally without emitting an event.
The base widget removes the FAB subtree while the route is active so it cannot
receive pointers or contribute tooltip or button semantics behind the modal
barrier.

The Material 3 sheet has a dismissible scrim, drag handle, 28dp top corners,
compact full width, a 640dp maximum content width on larger windows, top/side
safe-area handling, and bottom padding that follows the software keyboard or
bottom safe area. Standard-duration presentation requests focus only after the
route animation completes and after the editor mounts. Zero-duration
presentation requests focus in the immediately following mounted frame.

The route re-provides any `RendererResourceScope` captured at the FAB so
arbitrary OCaml child widgets keep their node-scoped resources inside the
Navigator overlay. A decisive downward composer drag, a sheet drag, a scrim
tap, or Escape dismisses and unfocuses without clearing or committing. Short,
upward, and decisive-horizontal composer gestures do not dismiss. Focus loss
alone keeps the sheet open.

Disablement during entrance or while presented dismisses to the disabled FAB
and preserves the controller draft. Flutter widget identity supplies the reset
boundary: a changed logical key synchronously removes the owned route before
disposing its controller and focus node, then creates fresh native-local state.
There is no retained inline expansion mode or application-host fallback.

## Alternatives considered

### Add a general logical animation node

It can interpolate geometry but cannot own an uncontrolled editor controller,
focus scheduling, a Navigator route, modal semantics, or local dismissal. It
would broaden the protocol while leaving the continuity boundary unsolved.

### Switch OCaml children or use an inline cross-fade

An OCaml state switch requires an event and frame for every presentation or
dismissal and replaces unrelated subtrees. An inline cross-fade does not
provide the requested modal sheet, scrim, route focus, or dismiss behavior.

### Put the route in a consumer host

That splits supported framework behavior across repositories, adds a host side
channel, and is overwritten when generated packages are synchronized.

### Extend MessageComposer into both public roles

The existing widget's contract begins as an editor. Making its default state a
FAB would break that behavior, while a mode flag would conflate two different
lifecycles. Shared private rendering remains allowed.

## Consequences

- OCaml and Dart expose kind `7`, version `1`, symmetric strict codecs, ordered
  icon/button children, typed raw-text events, and documented public APIs.
- The collapsed widget contains one real enabled or disabled
  `FloatingActionButton.extended`, aligned to logical end, and no editor.
- A FAB press presents one Material modal bottom sheet with a scrim, drag
  handle, 28dp top corners, and one MessageComposer-equivalent editor.
- Standard motion focuses after route completion; zero duration focuses after
  the mounted sheet frame; stale focus cannot occur after dismissal,
  disablement, key replacement, or disposal.
- Downward drag, scrim tap, and Escape dismissal preserve empty, whitespace,
  and Unicode drafts. Horizontal intent, upward and short downward gestures do
  not dismiss; focus loss alone keeps the sheet open.
- Buttons preserve position, visibility, style, enablement, and exact
  current-text event behavior. Text changes are emitted without trimming.
- LTR, RTL, 320-point width, 640dp desktop width, text scale near 3.2, safe
  areas, keyboard insets, standard motion, and reduced motion do not overflow.
- Existing standalone `MessageComposer`, renderer registry, codec, OCaml, and
  protocol behavior remains green.
- No Dune file, OCaml file below `spec/`, consumer repository, generated
  `.bonsai-flutter` path, or compatibility presentation mode is changed or
  added.

## Risks

- Navigator overlays do not inherit arbitrary application scopes. The route
  must explicitly re-provide renderer resources for OCaml children.
- Removing a keyed widget while its modal route is active requires synchronous
  route removal before controller and focus-node disposal.
- Material 3 recommends modal bottom sheets primarily for mobile. macOS is a
  verification target for this shared implementation, not a commitment to its
  final desktop information architecture.

## Questions

None.
