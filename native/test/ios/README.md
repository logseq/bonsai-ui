# Physical Journal native UI acceptance

This host runs the existing OCaml scenarios in `native/test/runtime_fixture.ml`
through the production framework. The Swift application only selects an
entrypoint; XCTest drives actual native controls. It does not implement a
replacement application reducer. No Simulator target is supported.

Build the current framework's iOS install artifacts with the selected cross
toolchain, then compile the existing fixture sources:

```sh
python3 tool/build_native_ios_fixture.py \
  --findlib-config "$IOS_FINDLIB_CONFIG" \
  --framework-library "$CURRENT_IOS_FRAMEWORK_LIB" \
  --ocamlfind "$IOS_OCAMLFIND" \
  --build-directory "$FIXTURE_BUILD"
```

`CURRENT_IOS_FRAMEWORK_LIB` is the worktree cross-build's
`install/default.ios/lib`, produced by `dune build -x ios bonsai_swiftui.install`
with the same build directory used for the application objects. The findlib
configuration must select an iOS 26 compiler, its target standard library, and
the target dependency closure. Host `.cmx`, `.o`, or `.a` files must never be
copied into that closure. The helper validates framework selection and the final
IOS/arm64/26.0 complete object.

Generate a host using `tool.swiftui_xcode_host.generate_project` with:

- `application_root`: this directory;
- `framework_root`: the current repository;
- `product_name`: `JournalNativeAcceptance`;
- both bundle identifiers: `org.bonsai-swiftui.test.journal-native`;
- `host_directory`: a fresh directory under `_build`;
- `development_team`: the existing local development team.

Stage `runtime_fixture.o` at
`<host>/Native/iphoneos/Release/runtime.complete.o`. After the physical-device
preflight, run the generated `JournalNativeAcceptance-iOS` scheme in Release
against the exact device identifier, supplying a new result-bundle path. Its
application-owned UI bundle covers List positioning, native navigation and Back,
outline targeting and row actions, toolbar updates and bottom-bar groups, Form,
controlled alert/dialog responses, menu/swipe/navigation coexistence on the same
row, and ordinary context menus inside a native sheet. Preserve the `.xcresult` and inspect its
original screenshots. UI Automation must be enabled on the device.

The iOS 26 native confirmation dialog may present a popover, omit disabled
actions, and use outside dismissal instead of a visible Cancel button. The tests
assert rejection of enabled interaction for disabled actions, explicit Cancel
on Alert, and exactly one response to outside dismissal. When a Cancel action is
provided, iOS routes outside dismissal through that action. Without one, the
response is `Dismissed`.
Toolbar commands may move into the system overflow menu after reordering; the
test opens that native menu before activating the command.
