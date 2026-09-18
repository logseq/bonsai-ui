# SwiftUI message composer

The ordinary `Native_widget.Message_composer` is implemented by the standard
SwiftUI kind-6/version-1 registration. `RenderTree` installs it with the
application's startup registrations. The expandable composer uses kind 7/version 3.
Both registrations are reserved against application replacement.

## Ownership and publication

The draft is explicitly ephemeral and native-owned. `NativeTextController` and
`TextSession` own its text, UTF-16 selection, composing range and local edit
revision. OCaml receives observations and exact raw-text button events. Sending
does not clear the draft. Changing the logical key creates a new empty editor;
a stable key retains it through changes to hint, line limit, enabled state and
action metadata. Removal, epoch replacement and session closure dispose native
delegates and callbacks.

Registrations now accept a typed `validateChildren` callback. It runs before
resource creation and publication, including when a frame changes children while
reusing decoded properties. Composer payloads validate reserved flags, positive
line limits, UTF-8 text, unique positive action IDs, visibility/style flags,
truncation, trailing bytes and exact action-child count. Failed candidate frames
leave the previous rendered tree intact.

Draft admission uses the existing one-MiB UTF-8 text-session limit. A rejected
edit restores the previous text/selection; a full native event queue also rejects
an edit without losing the draft. Reaching the text limit displays `Draft limit
reached`. Text-change detection compares UTF-8 bytes, preserving distinct
canonically equivalent Unicode spellings in the OCaml event stream.

## Inline SwiftUI composition

One native editor remains mounted within a SwiftUI surface. Its ideal height is
measured with the current native font, width and insets, then bounded by the
configured line count. Additional lines scroll. A collapse action reduces the
editor to one line and releases focus without replacing its controller or draft.
Native focus expands it again. A separate drag handle owns downward collapse;
text selection and editor scrolling do not share that gesture area. Reduced
motion removes the explicit size animation.

Action rows use logical leading/trailing placement and native plain/prominent
button styles. Empty/nonempty visibility trims whitespace; action events use the
untrimmed text. Whole-composer and per-action disablement are independent.
Arbitrary OCaml action children are decorative labels, with independent hit
handling and accessibility excluded. Their nested handlers cannot dispatch
through the core session.

## Evidence and remaining acceptance

`Composer_catalog` is included in Gallery and registered as `native-composer`
and `native-composer-focus` in the actual OCaml runtime fixture. Initial tests
failed with unregisteredKind(6). The integration tests cover input/actions,
decorative child isolation, configuration changes, selection/marked text,
resource disposal, queue pressure, size limits and malformed frames. A subsequent
regression reproduced a missed observation when composed e-acute changed to its
decomposed spelling; byte comparison fixes it. Five focused tests pass in
`/tmp/composer-focused-final.log` (2.882 seconds).

The independent SwiftUI App verifies programmatic native autofocus, five-line and
three-line height limits, exact raw actions, collapse/re-expansion, whitespace
visibility, stable editor identity and keyed reset. Its successful run is recorded
in `/tmp/composer-window.log` (23.792 seconds, before the final UTF-8 comparison
change). Physical keyboard/touch/drag, iOS keyboard avoidance, VoiceOver and
physical-device performance are not established by this AppKit window test.
The desktop was locked at that checkpoint; those tests did not establish physical
keyboard interaction or complete desktop capture.


Final verification passes 363 Swift tests in 81 suites
(`/tmp/composer-swift-final.log`, 321.771 seconds), all three platform checks
(`/tmp/composer-platforms-current.log`, 17.753 seconds) and the independent
composer window (`/tmp/composer-window-final.log`, 22.786 seconds). Physical iOS
validation remains compilation-only at this checkpoint.

## Expandable presentation

`Native_widget.Expandable_message_composer` places the same editor in a native
SwiftUI Sheet and NavigationStack. The system toolbar provides Close and explicit
Action/Confirmation/Cancellation roles; there is no sheet drag target, chevron
or manually placed action row. See [sheet actions](swiftui-expandable-composer.md). There is no second card background. The
launcher supports Compact and Extended presentation; its duration and curve
control the launcher change, while Sheet transitions use the platform behavior.
Zero duration and reduced motion suppress the explicit launcher animation.
The Sheet uses fitted sizing on macOS and medium/large detents on iOS.

A presentation generation is independent of native property generations.
Closing suspends the editor immediately and keeps background input blocked
until native dismissal completes. Reopening retains the editor, draft and
selection and requests focus again. Configuration changes keep the current
Sheet mounted. Disablement keeps it mounted, inert and dismissible. Removal,
key replacement, epoch replacement and closure invalidate presentation leases
and dispose the resource. Old bindings cannot close a later presentation.

`BonsaiNativeContext.canInteract` synchronously queries the owning session before
local native actions. It checks the snapshot generation, mounted identity,
presented properties/bindings/children, application visibility and modal input
ownership. Native modal resources block input outside their owned subtree from
the open request through dismissal completion. This complements event admission;
a stale `isPresented` snapshot alone cannot authorize a local presentation.
Launcher and action children are decorative and never mount independent handlers.

`Expandable_composer_catalog` is included in Gallery and registered as
`native-expandable-composer` in the real OCaml fixture. The initial three tests
failed with `unregisteredKind(7)` and allowed reserved-kind replacement
(`/tmp/expandable-red.log`). After implementation, all three pass
(`/tmp/expandable-green.log`, 7.730 seconds): real Sheet open/close/reopen,
raw events, editor/selection retention through Compact configuration, disabled
presentation, resource disposal on removal/key replacement, background gating,
stale button rejection and malformed frame validation.

The independent SwiftUI App passes in `/tmp/expandable-window.log` (25.470
seconds), verifying native focus on open/reopen, Escape dismissal, five-/three-line
height limits and retained draft/selection. Expanded tests additionally exercise
marked text, stale bindings, session restart and accepted duration/curve/style
variants. All eight ordinary/expanded focused tests pass in
`/tmp/expandable-focused.log` (11.750 seconds). OCaml `@all @runtest @fmt` passes
in `/tmp/expandable-ocaml.log`, with existing native linker stub warnings.
The full regression passes 366 Swift tests in 81 suites with a completed xUnit
report (`/tmp/expandable-swift-full.log`, 330.646 seconds). The three platform
checks pass (`/tmp/expandable-platforms.log`, 18.324 seconds), including physical
iOS 18 compilation and explicit Simulator/Intel rejection. A closure-call
formatting correction follows that full run; it does not change behavior.
All three independent windows pass against the formatted source
(`/tmp/expandable-native-windows.log`, 70.996 seconds): expanded composer,
ordinary composer and Mail inbox/expansion/Archive.
Physical iOS keyboard avoidance, touch dismissal,
VoiceOver, performance and complete desktop screenshots remain acceptance work.


The final focused run passes all eight composer tests
(`/tmp/expandable-focused-final.log`, 12.123 seconds). The Mail macOS development
bundle is rebuilt from this worktree (`/tmp/expandable-mail-build.log`), verifies
with deep/strict ad-hoc signing, and reports arm64 with minimum macOS 26.0.
Protocol generation, shared fixtures, viewport compile-failure checks, strict
handwritten Swift formatting, `git diff --check` and agent document validation
pass. The protected `ocaml/spec/` tree is unchanged. Existing linker and
`Semantics.swift` unused-result warnings remain; no warning-free build is claimed.
