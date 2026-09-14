# Standalone SwiftUI Gallery

Gallery uses the same application-owned OCaml/Swift structure and generated
Xcode hosts as the other ten examples. Its schema-3 configuration selects
macOS 26.0+ arm64 and physical iOS/iPadOS 18.0+ arm64. Simulator, Intel and
Catalyst are unsupported. The native-object Dune target is unconditional and
explicitly declares the Bonsai and UI libraries used by its entrypoint.

`swift/GalleryNativeViews.swift` registers native kind 1001/version 1 with a
UTF-8 property decoder, native SwiftUI Button, resource-local activation state,
logical children and typed events back to the OCaml handler. OCaml retains the
canonical card counter. Standard composer registrations remain framework-owned.
The App bundles Gallery's existing PNG and animated GIF resources.

## Build versus complete-page acceptance

The standalone-copy CLI test initially fails because Gallery has no native
configuration. After the port it builds an actual macOS App and compares both
bundled image resources with their source bytes: one test passes in 31.091
seconds (`/tmp/swiftui-gallery-host-green.log`). That result proves packaging,
not that the complete page can render.

`FullGalleryTests.swift` runs the real, complete OCaml `Gallery.component`
through `BonsaiSession`. It requires full-tree staging and presentation, invokes
the toolbar action, checks the updated OCaml counter and rejects a stale action
after session close. It uses a native-card registration fixture to admit the
application extension; this does not validate the App's own card UI.

The initial test rejects node 70 (EnvironmentBoundary). Removing that obsolete
Flutter wrapper exposes node 98 (Material elevated Button). Replacing Gallery's
Material Button/FAB samples with native Button/Label/ControlSize composition
initially advances the test to unsupported node 53 (KeyboardListener). The later
FocusScope and macOS KeyboardListener implementations remove that blocker: the
complete tree/presentation/toolbar test now passes in 0.321 seconds. It does not
mount every native control or validate the App-specific native card. Physical-iOS
KeyboardListener now has a UIKit capture implementation and node 53 is accepted
by the iOS renderer. Its physical keyboard propagation and complete native page
interaction remain unverified. No page is silently omitted and no unsupported
node is rendered as a placeholder.

The source port therefore does not establish a runnable full Gallery or complete
widget coverage. Remaining native widgets, their Gallery scenarios, physical
interaction, layout and accessibility acceptance remain required.

## EnvironmentBoundary removal

The old renderer implemented EnvironmentBoundary by constructing a MediaQuery
with the same current MediaQuery data. SwiftUI environment inheritance supplies
the native behavior without a separate logical wrapper. The constructor, private
node variant, protocol schema entry, driver mappings, OCaml codecs and generated
IDs are removed; the retired numeric ID 70 is rejected rather than aliased.
Native theme scopes, safe-area modifiers and host-environment event encoding
remain. Actual native environment observation/publication is still unfinished.

The retirement regression initially recognizes node 70 and fails while parsing
its old property shape rather than returning Unknown_node_kind. After removal,
the OCaml protocol regression passes with the required unknown-kind rejection.
The OCaml build/test/format/install gate also passes. Protected spec sources are
unchanged.

## Reproduction

With the worktree CLI and library environment from the repository README:

```sh
cd examples/gallery
"$BONSAI_SWIFTUI_CLI" sync-host
"$BONSAI_SWIFTUI_CLI" build macos --profile debug
```

Run the complete-page acceptance test from the repository root:

```sh
dune build native/test/libruntime_fixture.dylib
swift test --scratch-path _build/swift --no-parallel \
  --filter actualCompleteGalleryStartsAndDispatches
```

This command now passes on macOS. It proves full-tree staging, the presentation
handshake and OCaml toolbar dispatch; native page layout, all widget interactions,
App-specific card behavior and physical-iOS acceptance remain separate requirements.
