# Native Disclosure Groups

`View.disclosure_group` renders a SwiftUI DisclosureGroup with an application-owned
Boolean expansion state. It replaces Expansion_panel_list and Expandable_list;
there is no Material expansion model or specialized list event in the renderer.

```ocaml
View.disclosure_group
  ~key:(Key.int64 item_id)
  ~expanded
  ~on_changed
  ~label:(View.row ~spacing:6.
            [View.symbol ~name:"envelope" (); View.text "Details"])
  ~content:details
  ()
```

`on_changed` receives `Event.Payload.Bool`. The label may be composed content,
but the disclosure owns label interaction: nested label controls cannot emit
input. Native platform behavior determines header and disclosure-indicator
activation. The obsolete `can_tap_on_header` setting is removed.

Single or multiple expansion is application state. Give each keyed disclosure
a stable handler that updates the shared expanded-ID set. In single mode, an
accepted true request replaces that set with the requested ID. A false request
removes that ID. The Gallery also demonstrates rejecting requests and changing
policy while preserving an existing expanded item.

Finite content uses a Column or another ordinary layout. Scrollable content uses
`View.Scroll.vertical` and a bounded Body slot. Windowed content uses the common
Collection contract with stable keys and sizes reflecting current expansion;
there is no disclosure-specific finite/scrollable/sliver family.

## Native ownership

Toggle and DisclosureGroup share a BooleanControlController for optimistic
native state, pending-request serials, rejected-request restoration, stale binding
fences and disposal. Their native styles and child ownership remain distinct.
A disclosure has a label and content; a Toggle has only its label. A native
request uses the last presented revision and current matching handler/configuration.
An unchanged OCaml reply still resolves its pending native request.

Body input requires the current and displayed states to be expanded, the native
controller to remain expanded, and enabled ownership in both states. This also
blocks input during an unpresented expansion or an optimistic collapse. Collapsed
content is explicitly disabled, excluded from hit testing and hidden from
accessibility. Disabling a disclosure disables its header and expanded content.
Lifecycle animation completions can still occur in visible disabled content.

The logical body and its native text controller remain owned by the same nodes.
The native adapter can be rehosted without losing the local draft and selection.
Collapsing releases editor focus, and hidden edits cannot modify the retained
draft. Reopening restores the existing editor state.

## Protocol and verification

Node 133 is now `disclosure_group` with two required Boolean properties,
`expanded` and `enabled`, property mask 3, two children and a Value_changed binding
only when enabled. Event 44 and the former policy/expanded-ID/panel payload are
removed. Trailing legacy bytes, invalid flags, child arity or bindings reject
an entire staged transaction. There is no old-payload decoder.

Initial tests failed on unsupported node 133. Native raster comparisons now
match independent SwiftUI DisclosureGroup expressions when expanded and collapsed.
Malformed payload tests check atomic rejection. The real Gallery runtime tests
single/multiple expansion, policy changes, accepted and rejected requests,
reordering with node identity, nested-label isolation, disabled and hidden-body
input, presentation fences and session closure.

The native App presses actual disclosure indicators at 640 and 360 points. It
checks native expansion values, explicit collapse/reopen, rejected-request
restoration, single/multiple policy, disabled headers and body controls, hidden
body accessibility and reordering. A native editor test initially showed that
collapsed retained content remained editable; explicit content disabling now
preserves the draft and selection and rejects hidden editing.

These checks are not screenshots or physical-device acceptance. Pointer and
keyboard behavior, VoiceOver, physical iOS editing/IME and visual acceptance of
the complete Gallery remain outstanding. Other legacy Material/expressive
families and the combined standalone Gallery still require migration.
