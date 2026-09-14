# Native sheet and dialog composition

`View.Sheet.create` presents controlled modal content. `View.Sheet.full_screen`
uses an iOS fullscreen cover and a native macOS sheet. They replace the Material
Dialog alert/simple/fullscreen surfaces and Bottom_sheet / Side_sheet surfaces.
Titles, icons, dividers, descriptions, choices and actions are ordinary Views;
there is no separate Material dialog property bag.

```ocaml
View.Sheet.create
  ~presented:show_details
  ~sizing:View.Sheet.Fitted
  ~interactive_dismiss:true
  ~detents:[View.Sheet.Medium; Large]
  ~initial_detent:View.Sheet.Medium
  ~on_presented_changed:dismiss_details
  ~content:
    (View.column
       [ View.text "Message details"
       ; View.divider ()
       ; View.text "Review the details before continuing."
       ; View.button ~on_press:confirm ~child:(View.text "Confirm") ()
       ; View.button ~on_press:close ~child:(View.text "Close") ()
       ]
     |> View.padding ~insets:(Layout.Edge_insets.all 16.)
     |> View.frame ~width:320.)
  background
```

OCaml owns `presented`. Native dismissal sends `Event.Payload.Bool false` through
`on_presented_changed`; opening and programmatic closing use ordinary model
actions. A rejected native dismissal restores the presentation. Set
`interactive_dismiss:false` to prevent native dismissal entirely while retaining
explicit application actions. `full_screen` requires explicit application
closing and exposes no drag-detent configuration.

For regular sheets, detents default to `[Large]`, interactive dismissal and the
drag indicator default to true, and the initial detent defaults to the first
listed entry. Detents must be nonempty and unique, and the initial detent must
belong to the set. iOS uses native medium/large detents and the native drag
indicator. The selected height is local SwiftUI presentation state; it resets
on a new canonical presentation or configuration change. Rejecting dismissal or
resuming visibility does not change that initial-selection contract. macOS uses
native sheet sizing without simulating an iOS drag handle or mobile fullscreen
window. Content bounds and native platform layout determine its size.

## Native sizing

`~sizing` accepts `Automatic` (default), `Fitted`, `Form` and `Page`, mapped to
SwiftUI's corresponding presentation sizing policies. `Fitted` proposes the
content's ideal size; `Form` and `Page` use system proposals. These proposals
remain subject to available window space and the content's frame constraints.
A form/page presentation is not guaranteed to be larger than a fitted one.
iOS detents separately control sheet height; `Fitted` is not a promise of an
automatic content-height iPhone detent. Compose bounded Scroll views inside the
sheet for scrollable content. Fullscreen covers do not expose a sizing override.

The native Gallery regression measures a 360 by 420 point fitted sheet and
checks that form/page policies use a different height while respecting a
360 point minimum in its 500 by 460 point parent window. It also retains the
existing actions, modal input fencing and dismissal checks for every policy.
Sizing values outside 0...3 and nonautomatic fullscreen sizing reject the frame.

See [Apple: presentationSizing(_:)](https://developer.apple.com/documentation/swiftui/view/presentationsizing(_:))
and [Apple: automatic sizing](https://developer.apple.com/documentation/swiftui/presentationsizing/automatic).

## Presentation ownership

Popover and Sheet share one presentation controller implementation. Each logical
node still owns its own controller, immutable callback generation, pending
request serial, canonical visibility and native appearance state. Configuration,
content and handler replacement invalidate prior callbacks. Reading a stale
binding cannot renew its ownership.

The first child is the background/presenter and the second is modal content.
Closed content stays logically mounted but cannot receive interaction or native
focus. A sheet's content becomes interactive only after its owning frame is
acknowledged and its native appearance is observed. Modal input admission also
blocks background siblings outside the sheet's own subtree. Nested popovers
inside the sheet remain independently controlled.

The renderer maintains a list of presentation nodes so modal checks need not
scan every render node for each input. Session hiding and shutdown close native
presentations without generating artificial model dismissals. Reappearance can
restore canonical visibility. Presentation nodes are disposed on logical removal
or epoch replacement; retained child identity is independent of temporary native
view materialization.

Node 73 (`sheet`) has property mask 127: presented, fullscreen, detent bit set,
initial detent, interactive dismissal, drag-indicator visibility and sizing. It requires
two children and one existing `value_changed` binding. Medium is bit 1, Large is
bit 2; the initial code is 0/1. Fullscreen encoding requires Large, initial Large,
interactive dismissal disabled, no indicator and Automatic sizing. Constructor and codec validation
reject invalid configurations; Swift staging also rejects malformed flags,
children, bindings and truncated updates transactionally. Old simple/fullscreen
dialog nodes 134/135, their option codec and event 45 were removed.

## Evidence and remaining work

The actual `Sheet_catalog.component` is embedded as `native-sheet` and included
in Gallery. Five presentations exercise alert-like content, enabled/disabled
account choices, bottom content, inspector-style content and fullscreen content.
Native windows verify repeated actions, selection, blocked background and
same-window sibling input outside the presentation subtree,
nested popover actions, disabled interactive dismissal, rejected/accepted Escape
cancellation, stale handler callbacks, hiding/resuming, programmatic closing,
retained child identity and shutdown. The initial tests failed on unsupported
nodes 73 and 136. Popover's existing native regression also passes with the shared
controller. Protocol staging and OCaml constructors cover invalid detent domains.

The old `View.navigator`, `View.page` and `Navigation.Modal_*` APIs, their
wire nodes 66/67, route property codecs and route-pop event 16 are removed.
Use `View.Navigation_stack` for destination paths and `View.Sheet` for modal
visibility. Result values belong to the application's OCaml model and ordinary
actions. A regression rejects a previously valid Page update. No legacy route
decoder or compatibility wrapper remains in the OCaml/Swift backend.

Scaffold's persistent bottom slot now uses [page layout composition](swiftui-page-layout.md).
Native focus, keyboard avoidance and scroll-versus-detent gesture acceptance remain
required; deleting the old route test harness does not establish these behaviors
on the replacement platforms. Arbitrary Flutter barrier colors/labels, route
animation durations, receding-page transforms, restoration IDs and custom handle
semantics are removed in favor of native presentation behavior and application
state. They are not accepted as ignored parameters.

Physical keyboard/pointer interaction, VoiceOver, focus/IME inside presentations,
native iOS detent dragging, compact-size adaptation, fullscreen device behavior,
concurrent/nested sheet arbitration and performance remain unverified. iOS source
compilation alone is not OCaml cross-linking or device-runtime acceptance. The
complete standalone Gallery and real Mail screenshots remain outstanding.
