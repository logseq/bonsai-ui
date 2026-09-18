# Native extension API review

All 39 baseline `Native_widget` values and 36 named constructors now have
individual dispositions in the [inventory](swiftui-widget-inventory.json).
Current declaration, Swift implementation, real Gallery fixture and test-file
references were checked. This records API coverage, not complete physical-device
acceptance.

| Baseline family | Current direction | Event and ownership changes |
| --- | --- | --- |
| Generic Extension/Capability helpers | Typed OCaml schema and `BonsaiNativeViews` registration | Exact kind/version and capability checks remain; Swift owns resources and native content. |
| Morphing_surface | Core `View.Morphing_surface` | Remove opaque kind/payload and no-op handler; OCaml supplies active content and Swift animates its surface. |
| Slidable and auto-close wrapper | Core `View.Swipe_actions` | Independent Unit Press handlers replace the extension event union; native List owns reveal and closing; obsolete group policies are removed. |
| Navigation_shell | Native split columns and keyed Tabs | Complete split-state requests and stable page keys replace drawer Boolean and selected index. |
| Message_composer | Standard SwiftUI kind 6/version 1 | Preserve typed text/action observations and an explicitly ephemeral native draft. |
| Expandable_message_composer | Standard SwiftUI kind 7/version 3 | Native launcher and Sheet share one retained editor; remove Scaffold placement and old schema decoding. |

The removed extension kind and event constants have no numeric aliases. A
full-swipe action invokes an ordinary OCaml handler, which decides whether to
remove its row. Flutter pane motions, open/close thresholds, dismissal/resize
timing and integer flex are removed; native reveal policy and explicit action
extents determine presentation. Custom action content remains a decorative label
inside the action's native hit target.

Navigation bodies use bounded columns and keyed Tabs when all destination
states must stay mounted. The old arbitrary bottom-navigation slot and
drawer-enabled policy are not silently emulated. Applications choose their
native navigation structure explicitly. SwiftUI column visibility is a native
intent, not a promise to reproduce a Flutter drawer's geometry.

Composer leading/trailing placement, empty/nonempty visibility and Plain/Filled
emphasis remain, with native rendering. Whitespace controls visibility; events
preserve exact raw text. Sending does not clear the draft. Compatible changes
retain the editor, selection and marked text; logical replacement resets
ownership. Expanded/compact launcher changes retain an open Sheet, and closing
then reopening retains the draft. Launcher timing is separate from native Sheet
transition behavior.

Capability flags describe what an application registration supports; they do not
implement resources, accessibility or virtualization automatically. The actual
Gallery extension supplies its Swift factory and typed OCaml counterpart.
Standard composer registrations cannot be replaced by application registrations.

## Verification

The referenced Swift implementations and tests still match the complete
482-test, 106-suite macOS regression, so the suite was not repeated. Existing
coverage includes native resources, stale input, malformed extension payloads,
composer editing/selection, real Sheet presentation, swipe callbacks and native
split state. Family guides retain their precise interaction and device limits.

The public expandable-composer comment incorrectly said the SwiftUI registration
was missing. It now describes the existing implementation; no signature or
runtime behavior changed. Evidence and source hashes are recorded in
`_build/validation/swiftui-extension-api-review.json`.

Physical iOS IME, touch/swipe arbitration, VoiceOver and remaining family-specific
acceptance are still open. Reviewing these APIs does not complete those gates.
