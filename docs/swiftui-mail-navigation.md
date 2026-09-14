# Mail Navigation with Native Tabs and Split Columns

Mail now composes four application pages with `View.Tabs`. Its Mail page holds
`View.Navigation_split` with mailbox, message-list and detail columns. Both
containers consume bounded `View.Body.t` content, so typed Scroll and Collection
viewports fit directly into native framework slots without an unrestricted
viewport-to-view conversion. Gallery's split call site uses `Body.static` for
its ordinary content; the public API has no legacy plain-view overload.

## State and behavior

OCaml stores application destination, mailbox destination, selected message,
column visibility and preferred compact column. The selection key published to
the split is derived from the selected message; there is no second independent
selected-message field. The initial request is All columns with Content as the
preferred compact column. Native platform adaptation decides which columns are
visible at runtime.

| Action | Result |
| --- | --- |
| Select Mail, Chat, Spaces or Meet | Change only the selected application tab; keep all logical pages and Mail state mounted. |
| Select an unknown tab key | Ignore the request. |
| Menu | Request All visibility and the Sidebar compact column. |
| Select a mailbox | Clear old detail, notice and inline expansion, reset the materialized window, cancel stale paging and select Content. |
| Open a message preview | Mark the message read, select its detail and request the Detail compact column. |
| Native visibility change | Update visibility while preserving the selected message if the compact destination has not moved away from Detail. |
| Native return from Detail | Clear the selected detail and notice when the observed message key still matches. Preserve the expanded card and loaded list. |
| Stale native split event | Ignore the entire state request, including visibility, when its observed message key differs. |
| Detail Back, archive, delete or mark unread | Apply the action and select Content with no selected detail. |

The detail column has a visible placeholder when nothing is selected. Detail
content retains a message-derived key and a typed native Scroll body. The
message list retains its existing catalog/window identity and bounded rows.
The sidebar also scrolls within its native column.

## Removed architecture

Mail no longer uses `Native_widget.Navigation_shell`, `View.navigator`,
`View.page`, `Material.scaffold`, a custom four-button bottom bar, manual root
safe-area exceptions or a 720-point maximum root width. The unused
Navigation_shell OCaml API, private native-widget body-slot helper, Dart host,
registration/export and obsolete shell contract tests are removed. The generic
navigation capability is covered by native Tabs and Navigation_split tests.
The previous Mail Flutter host and `bonsai-flutter.sexp` configuration are also
removed. `examples/mail/swift/App.swift` provides the native entrypoint and the
Mail complete-object target no longer depends on a Flutter environment gate.
Other widget families still being migrated are not represented as compatibility
paths for this removed shell.

## Verification

The Mail test executable runs the actual Bonsai component. Tests now send native
Tab_selected and Navigation_split_changed events, replacing drawer-settled and
route-pop expectations. They check all four keyed tabs, retained application
page identities, loaded messages and card state, accepted and unknown tab keys,
compact sidebar/content requests, visibility-only changes, mailbox changes,
stale observed message keys and detail actions. Existing paging, collection,
read/star/archive/trash, attachment, outline and action-isolation tests remain.

The navigation checkpoint validation included 163 Swift tests, physical iOS 18
module typechecking and three standalone SwiftUI App scenarios. The sidebar
scenario repeats three native hide/show cycles. It exposed unchanged-echo
binding invalidation and final native-intent loss during pending presentation;
both now have deterministic regressions and fixes while stale-message and
hidden-page fencing remain enforced.

The typed Viewport fixture compiles a vertical collection/scroll body in the
content column and a horizontal body in detail. Existing Gallery native-runtime
and standalone system-control tests continue to cover the split renderer. These
checks distinguish application-model correctness from full Mail rendering.

The development build command `python3 tool/build_swiftui_example.py mail`
produces `examples/mail/apple/DerivedData/Build/Products/Debug/BonsaiMail.app`
from the real Mail OCaml object and SwiftUI entrypoint. Building and strict
ad-hoc signature verification succeed;
the subsequent native Mail window test also verifies inbox rendering, card
expansion and Archive action dispatch through the real OCaml model.

## Remaining runtime work

Mail uses [native morphing surfaces](swiftui-morphing-surface.md) and
[core swipe actions](swiftui-swipe-actions.md). Its complete tree now stages in
SwiftUI. The native window test checks a content column at least 340 points wide,
expands a message and archives it through the native accessibility action.
The extended standalone window scenario also finds all five mailbox buttons
and the detail placeholder, selects Archived through its native button, verifies
that the archived message appears there, and returns to Inbox without restoring
that message. This establishes mounted controls and actual OCaml mailbox
transitions, not visible pixels. NSView cache exports still omit sidebar pixels
and native background composition while the desktop is locked. The initial
test-ID lookup was corrected to use exposed native button labels; that lookup
failure was not an application defect.
Physical swipe/scroll arbitration, retained native focus, iOS compact/back
interaction and real Mail screenshots remain required. Synthetic mouse swipe
acceptance currently fails; the passing action test does not establish gesture
acceptance.
