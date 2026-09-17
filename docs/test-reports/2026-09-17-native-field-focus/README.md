# Native field focus retention

The production owner is NativeTextFieldController and BonsaiSession's mounted
content admission. A pure application reducer cannot execute native responder
availability. The existing hosted native parent fixture reproduces the defect
through public plain/secure field construction and a real OCaml parent update.

## Reproduction and repair

Before the repair, both NSTextField and NSSecureTextField lose their first
responder when a native parent update is pending acknowledgment. The confirmed
red run reports 14 failed expectations, including disabled controls, lost focus
and dropped input. The test originally relied on the AppKit autofocus selection;
the final test explicitly appends at the current UTF-16 length so selection does
not affect the input-delivery assertion.

The controllers now preserve existing focus during an eligible mounted-parent
update. Session admission retains continuous text edits for these fields through
the existing mounted-path check. Hidden, disabled, inactive, removed and disposed
controls remain fenced. Submission retains strict admission.

## Validation

- Native fixture build passed.
- 26 tests in six suites passed, including both hosted field variants, existing
  field/wire/session/event/focus tests and multiline mounted-parent regressions.
- Installed bonsai_swiftui_tool was refreshed successfully.
- The Journal Release build for generic iOS passed with signing disabled,
  compiling the UIKit implementation against the current SDK sources.
- macOS Journal acceptance host built and opened its isolated encrypted graph.
- No physical iPhone keyboard retest has been performed. macOS hosted native
  evidence establishes this responder bug and fix, but cannot prove that every
  cause of the reported iPhone symptom is eliminated.

Commands:

```sh
dune build native/test/libruntime_fixture.dylib
swift test --filter 'mountedFieldRetainsFocusAcrossNativeAncestorUpdates|TextFieldTests|TextFieldWireTests|TextSessionTests|TextEventTests|FocusScopeTests|mountedEditorRetainsFocusAcrossNativeAncestorUpdates'
opam reinstall bonsai_swiftui_tool -y
```

The application build command and output are retained in journal-ios-build.log.
Source hashes identify the tested working tree, which includes prior changes.
