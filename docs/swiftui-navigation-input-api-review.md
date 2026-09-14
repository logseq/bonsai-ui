# Navigation and input API review

This closes the primary API mapping for the final 43 baseline values and 55
named constructors. The [inventory](swiftui-widget-inventory.json) now records
an individual replacement or removal rationale for all 228 values and 175
constructors from baseline `39c486233d0a1a614c6cb1267a80fa19d6076fcc`.
This is mapping completion, not full behavioral or physical-device acceptance.

## Replacement contracts

| Baseline family | Current composition and meaningful changes |
| --- | --- |
| Environment boundary and theme | Remove the environment wrapper. The application boundary publishes native snapshots through `App.Context.environment`; SwiftUI inherits preferences in the existing graph. `View.theme` scopes native scheme, tint, font and control size. Material theme fields have no compatibility aliases. |
| Gesture, focus, hover and keyboard | Native adapters preserve typed events and presentation ownership. FocusScope observes eligible descendants. Hover `blocks_behind` replaces `opaque` without intercepting child activation. Keyboard propagation remains explicit; text controls own IME editing. |
| Semantics | Use `Semantics.t` and actual native control roles/state. Labels, hints, grouping, headings and custom actions remain explicit. Checked, enabled, focusable and obscured metadata cannot fabricate corresponding native behavior. |
| Navigator and page | `Navigation_stack` owns a separate bounded root and keyed destination path. Native Back requests one remaining strict prefix; OCaml accepts or declines it. Modal visibility uses `Sheet`. Flutter transitions and restoration IDs are removed. |
| Navigation bar and destinations | `View.Tabs` uses stable page keys, bounded page bodies, literal titles, SF Symbols, badge text and accessibility labels. Positional selection and arbitrary icon subtrees are removed. SwiftUI owns bar placement and appearance. |
| Material tab strip | Use a Segmented `Picker` with signed option IDs. A selection strip does not become a collection of application pages merely because both APIs were named Tabs. Primary/Secondary styling is removed. |
| Workflow Stepper | `Workflow.step/create` retain signed step identity and content. Indexed becomes Pending; current-step identity replaces an independent active flag. Per-step Press handlers capture IDs. Continue/Back actions are explicit; inactive bodies retain state while excluding input/accessibility. |
| Plain and rich help | `View.help` adds native help/accessibility hints. Rich help composes a controlled `Popover` and independent Buttons. Neither preserves a Material tooltip renderer. |
| Dialog, bottom sheet and side sheet | `Sheet` composes ordinary title/icon/body/choice/action content with OCaml-owned visibility. iOS uses native detents/fullscreen cover; macOS uses native sheet sizing. Persistent sidebar/inspector content uses Split and Body layout. |
| Text fields | Use native plain/secure fields and a multiline editor. Revisioned text, UTF-16 selection, marked text and byte limits remain. Keyboard and submit-label configuration are typed; Filled/Outlined chrome becomes native presentation. Accessories and errors use ordinary composition. |
| Dropdown | Single selection uses Picker; multiple selection uses an OCaml-owned set and keyed Toggles. Search/query filtering and loading/empty/error states compose fields, progress, text and actions. Single-selection evidence alone does not establish the combined dropdown behavior. |
| Search | Inline field/results, anchored Popover or full-screen Sheet share native editing. OCaml owns query, suggestions and opening/closing policy. Ordinary transitions replace separate search-open/search-close wire events. |
| Page bars | Navigation titles and semantic Toolbar items replace top bars. Fixed Body children replace persistent bottom bars. Hero/section composition replaces Sliver AppBar; floating/snap, forced elevation and Material height/centering flags are removed. |
| Rail and drawer | Native two/three-column Split owns adaptive column presentation. Sidebar groups, destination Buttons, labels and primary actions are ordinary bounded content. OCaml keeps selection and accepts complete visibility/compact-column requests. |
| Toolbar | Each keyed native item contains an ordinary control. Per-action handlers capture IDs; SF Symbols replace the closed icon enum. Semantic placements replace Floating/Docked, axis, inline-count, expanded and active-action property bags. |

Each inventory entry records its exact current declaration, parameter
disposition, renderer, relevant tests and available Gallery component/fixture.
The remaining named variants include navigation-bar presentation options,
workflow layouts/states, text-field chrome, FAB position, split-button style,
dropdown content/selection, civil-picker modes/formats, tab-strip appearance,
rail modality, toolbar placement/icons and search presentation.

Date pickers always expose native year/month/day selection; initial Day/Year
panel modes are removed. Explicit 12/24-hour time formats remain, with System
added. FAB placement and split-button appearance belong to parent layout and
independently composed controls, respectively.

## Evidence and remaining work

Referenced Swift implementations and Swift test sources match the recorded
482-test complete macOS regression. No runtime implementation changed and that
suite was not rerun for this mapping update. Search additionally has the
standalone native-window test that exercises inline, anchored and fullscreen
composition through actual OCaml handlers and AppKit editing.

The inventory deliberately leaves behavioral acceptance pending. In particular:

- Scoped theme variation now has a shared interactive Gallery component and
  real OCaml/native-window regression; see [host environment](swiftui-host-environment.md).
  Its physical iOS interaction remains open.
- The [composed Dropdown](swiftui-dropdown.md) now has a combined native-window
  regression covering query/loading/error/multiple-selection behavior at two
  widths. Physical iOS and accessibility acceptance remain open.
- Auxiliary Layout, Style, Theme, Semantics and editing contracts are broader
  than this primary value/constructor inventory.
- Physical iOS keyboard/IME, focus, gestures, adaptive navigation, presentations
  and accessibility remain device gates. Existing macOS tests and iOS builds
  do not establish those interactions.

The [implementation decision](agent-guide/proposed/architecture/2026-09-11-swiftui-only-apple-backend.md)
retains the full migration completion criteria. No component is promoted to
complete solely by this document or its inventory mapping.
