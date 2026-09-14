# SwiftUI Toggle

`View.toggle` is the single controlled Boolean control. It replaces
`Material.checkbox`, `Material.switch`, `Cupertino.switch` and
`Material.Toggle_button`. Their public constructors, private OCaml nodes,
wire kinds and generated schema entries are removed without aliases.

```ocaml
View.toggle
  ~key:(Key.string "notifications")
  ~style:View.Toggle_style.Switch
  ~value:notifications_enabled
  ~enabled:true
  ~on_changed:notification_change
  ~label:(View.text "Notifications")
  ()
```

`on_changed` receives `Event.Payload.Bool`, representing the requested value.
The handler must set that value rather than invert its existing state. OCaml
can accept, alter or ignore the request. The label is ordinary composed content;
conditional icons and labels are derived from the same OCaml value. Independent
interactive label descendants cannot dispatch input through a Toggle owner.
Headless queries expose role `toggle` for every style.

## Native styles and accessibility

Automatic, Switch and Button use native SwiftUI Toggle styles. Checkbox uses
the native macOS checkbox and an explicit SwiftUI checklist style on iOS,
with a square/checkmark symbol and a minimum 44-point height. Its accessibility
representation uses a native Toggle bound to the same value. No mixed-state
contract is introduced; the replaced controls expose Boolean values.

The native label and control are combined into one accessibility element. The
disabled modifier is applied after that combination: real macOS tests exposed
an otherwise enabled accessibility element for a disabled Switch. The tests
verify labels, numeric checked state, activation and disabled state across all
four styles. The composition uses Apple's
[ToggleStyle](https://developer.apple.com/documentation/swiftui/togglestyle) and
[ToggleStyleConfiguration](https://developer.apple.com/documentation/swiftui/togglestyleconfiguration).

## Protocol and state ownership

Node 44 carries value, enabled and style, using property mask 7. It owns exactly
one label child and, when enabled, one Value_changed binding. Disabled controls
publish no binding. The transactional decoder rejects invalid booleans, unknown
styles, malformed bindings, missing labels and truncated property data.

Swift retains a local value while a request is pending. Consecutive requests for
the same control, handler and displayed revision coalesce to the final Boolean
intent. Per-request serials prevent an older response from clearing a newer
request. A no-diff response restores the authoritative OCaml value and permits
another interaction. Native binding generations reject callbacks invalidated
by authoritative state changes, changed configuration, disabling or disposal.

Session admission requires matching runtime identity, displayed ownership,
enabled configuration, style, label identity and handler. An in-flight value
echo alone does not reject the final native intent. Hidden tab/morph branches,
disabled controls and removed sessions remain unable to dispatch.

## Validation and remaining work

`ToggleTests.swift` exercises malformed frames and real macOS native controls.
The actual Gallery `toggle_component` includes all four styles, controlled
enabled state and a handler rejection mode. Its native tests verify accepted
and unchanged responses, retained nodes, final intent across an unpresented
echo and stale disabled bindings through the production OCaml bridge.

Todo and Gallery now use the core API. Gallery also replaces the former
multi-selection segmented control with [keyed Toggle groups](swiftui-multiple-selection.md)
sharing one OCaml selection set. The rest of the Flutter backend and its
copied integration fixtures still await global deletion; these obsolete hosts
are not alternative Toggle renderers. Physical iOS interaction, VoiceOver,
pointer/keyboard acceptance and final Gallery visual verification remain
required in the complete migration.
