# OCaml-Owned Application ThemeData

## Problem

The current `Bonsai_flutter_ui.Theme` model is a local widget-subtree theme,
not the application theme. `Theme.t` contains only `brightness` and
`color_seed`, and `Ui.Widget.theme` serializes those values into an ordinary
`Theme` node. The Flutter registry renders that node as:

```dart
Theme(
  data: ThemeData(
    brightness: props.brightness,
    colorSchemeSeed: Color(props.colorSeedArgb),
  ),
  child: child,
)
```

This arrangement has four ownership problems.

1. The generated managed host constructs a separate outer `MaterialApp`
   before the native runtime has produced a frame. That `MaterialApp` uses
   Flutter's default `ThemeData`, while the OCaml theme exists only below
   `MaterialApp.home`.
2. Custom hosts and host adapters may also construct or wrap the application
   with Flutter-owned theme state. There is no protocol-level assertion that
   the application has exactly one authoritative theme.
3. A subtree `Theme` does not configure `MaterialApp.theme`, `darkTheme`,
   `highContrastTheme`, `highContrastDarkTheme`, or `themeMode`. Application
   overlays and framework-owned shell behavior can therefore observe a
   different theme from the logical widget subtree.
4. `ThemeData(useMaterial3: true)` is currently an implicit Flutter 3.44
   default. Seed-to-`ColorScheme` generation and every unspecified theme field
   remain Flutter-version defaults rather than an explicit OCaml contract.

The current public surface is also too narrow for an application design
system. It cannot describe light and dark variants, high-contrast variants,
theme mode, seed-generation strategy, contrast level, semantic color roles,
Material typography roles, font families, density, tap-target policy, shape
tokens, or component defaults.

Directly exposing every `ThemeData` constructor parameter is not a suitable
fix. Flutter 3.44's `ThemeData` accepts Flutter-only objects such as
`WidgetStateProperty`, `InteractiveInkFeatureFactory`, `ThemeExtension`,
`Adaptation`, and more than forty component-theme classes. Mirroring that API
would couple the OCaml surface and wire protocol to Flutter implementation
details and would conflict with the renderer-independent component design.

The desired ownership guarantee needs a precise definition:

- every `ThemeData` installed on the framework-owned `MaterialApp` is built
  from values serialized by OCaml;
- Flutter may select among OCaml-supplied light, dark, and high-contrast theme
  variants, but must not synthesize an unspecified application theme;
- the generated host, host adapter, and `BonsaiFlutterRoot` API expose no
  parallel application-theme input;
- a theme update and its corresponding logical widget tree commit atomically;
  and
- local subtree themes remain explicit overrides and cannot accidentally
  become a second application-theme owner.

## Evidence from the current architecture

- `ocaml/ui/theme.ml` defines `Theme.t` as only `{ brightness; color_seed }`
  and supplies light plus `rgb(103, 80, 164)` defaults.
- `protocol/schema.sexp` gives node kind 69 two properties: `brightness` and
  `color_seed`.
- `flutter/packages/bonsai_flutter/lib/src/renderer/widget_registry.dart`
  constructs a fresh `ThemeData` for that logical node rather than deriving
  from or updating the outer `MaterialApp` theme.
- `bonsai_flutter_tool/lib/host.ml` generates
  `MaterialApp(title: ..., home: BonsaiFlutterRoot(...))` and passes that
  widget to `BonsaiFlutterHostAdapter.buildHost`.
- `BonsaiFlutterRoot` owns the `NodeStore`, but it currently returns only
  loading, error, or `BonsaiFlutterView` content. It does not own the
  `MaterialApp` shell.
- `App.create` components return only `Widget.t Bonsai.Cont.t`; there is no
  application-level render result in which a theme can change together with
  the widget root.
- `Environment.snapshot` already reports platform brightness and high-contrast
  state, so applications can observe those values. The application shell does
  not currently expose an OCaml-owned policy for selecting theme variants.

## Proposal

Adopt the following application-theme architecture.

### Separate theme data, application policy, and subtree overrides

Expand `theme.ml` around three distinct concepts:

```ocaml
module Theme : sig
  module Color_scheme : sig
    type dynamic_variant =
      | Tonal_spot
      | Fidelity
      | Content
      | Monochrome
      | Neutral
      | Vibrant
      | Expressive

    type t

    val from_seed
      :  color:Style.Color.t
      -> ?variant:dynamic_variant
      -> ?contrast_level:float
      -> unit
      -> t
  end

  module Typography : sig
    type t

    val material
      :  ?font_family:string
      -> ?font_family_fallback:string list
      -> ?display_large:Style.Text_style.t
      -> (* remaining Material 3 text roles *)
      -> unit
      -> t
  end

  module Shape : sig
    type t

    val create
      :  ?extra_small:float
      -> ?small:float
      -> ?medium:float
      -> ?large:float
      -> ?extra_large:float
      -> unit
      -> t
  end

  type visual_density =
    | Adaptive
    | Standard
    | Comfortable
    | Compact

  type tap_target_size =
    | Padded
    | Shrink_wrap

  type data

  val material
    :  brightness:Style.Brightness.t
    -> color_scheme:Color_scheme.t
    -> ?typography:Typography.t
    -> ?shape:Shape.t
    -> ?visual_density:visual_density
    -> ?tap_target_size:tap_target_size
    -> unit
    -> data

  type mode =
    | System
    | Light
    | Dark

  type application

  val application
    :  mode:mode
    -> light:data
    -> dark:data
    -> ?high_contrast_light:data
    -> ?high_contrast_dark:data
    -> unit
    -> application
end
```

The public surface follows this separation:

- `Theme.data` describes one complete `ThemeData` input;
- `Theme.application` describes the light/dark/high-contrast set and selection
  policy installed on the one `MaterialApp`; and
- `Ui.Widget.theme` applies one `Theme.data` as an intentional subtree
  override and never changes application theme mode.

When a high-contrast value is omitted, Flutter must reuse the corresponding
OCaml-supplied light or dark `Theme.data`; it must not construct a default
high-contrast `ThemeData`. Both light and dark values are required so `System`
mode never falls back to Flutter defaults.

In `System` mode, Flutter immediately selects among the complete
OCaml-supplied light, dark, and high-contrast variants. Platform brightness and
high-contrast changes do not wait for an OCaml event round-trip. Flutter owns
only variant selection; it does not construct or modify any selected
`ThemeData` input.

`useMaterial3` should be fixed explicitly to `true`, not exposed as an option.
The pinned renderer targets Material 3, and allowing Material 2 would double
the component default and testing contracts.

### Use renderer-neutral design tokens

The initial expanded surface should model stable Material concepts rather
than Flutter classes:

- a seed-generated color scheme with dynamic scheme variant and validated
  contrast level;
- all Material 3 typography roles, plus font family and fallback names;
- a small shape scale expressed as finite non-negative corner radii;
- visual-density and minimum-tap-target policies.

The first release does not include explicit semantic color-role records or
per-component themes. Components inherit the `ColorScheme`, typography, shape,
density, and tap-target mapping. A later decision may add renderer-neutral
component tokens after a concrete requirement demonstrates that the core token
model is insufficient.

The first proposal should not expose raw `ButtonStyle`,
`WidgetStateProperty`, `ThemeExtension`, `TargetPlatform`, splash factories,
page transition builders, Cupertino theme objects, or arbitrary Dart payloads.
Platform remains environment-owned rather than theme-owned. System dynamic
colors are not supported because enabling them would let the platform override
OCaml-supplied colors and violate deterministic theme ownership.

Font-family names can be serialized, but font assets remain a Flutter host
packaging responsibility. Documentation and validation must distinguish
selecting a bundled family from bundling that family.

### Make application theme part of the atomic render result

Introduce an application-level render value rather than inferring global
theme from an arbitrary node in the widget tree:

```ocaml
module App.View : sig
  type t

  val create
    :  theme:Bonsai_flutter_ui.Theme.application
    -> body:Bonsai_flutter_ui.Widget.t
    -> t
end

val App.create
  :  ?name:string
  -> ?trace:(string -> unit)
  -> (Context.t -> Bonsai.Cont.graph -> App.View.t Bonsai.Cont.t)
  -> App.t
```

`App.create_with_worker` should use the same render result. Every maintained
application must migrate to `App.View.create`; the old widget-only result path
should be removed rather than wrapped with an implicit default theme.

This shape makes theme selection reactive. An OCaml state change can replace
the application theme and body in one Bonsai stabilization without a Dart-side
theme controller or a second application state store.

### Store application theme outside the logical node tree

Add a typed application-theme operation or frame section rather than a
`MaterialApp` widget node. The application shell is unique global state, not a
repeatable or keyed child.

The preferred protocol behavior is:

- every full snapshot contains exactly one complete application-theme value;
- an incremental frame contains an application-theme update only when its
  logical value changes;
- the Dart decoder validates all enum values, bounded collections, finite
  values, contrast ranges, non-empty font names, and light/dark consistency;
- `NodeStore.prepare` validates the theme and widget operations together;
- `NodeStore.commit` publishes the new theme and widget root atomically; and
- equality and fingerprints include every serialized theme field but never
  contain Flutter objects.

The nested theme encoding should be a bounded structured protocol type, not
JSON, an opaque Dart object, or one protocol property per `ThemeData`
constructor argument. A single application-theme changed field may contain
four structured `Theme.data` values and the mode. Local `Theme` nodes should
reuse the same `Theme.data` codec.

### Move the one MaterialApp into BonsaiFlutterRoot

After the first valid full snapshot, `BonsaiFlutterRoot` should build the only
framework-owned `MaterialApp`:

```dart
MaterialApp(
  title: committedApplicationTitle,
  theme: decodeTheme(committedTheme.light),
  darkTheme: decodeTheme(committedTheme.dark),
  highContrastTheme: decodeTheme(
    committedTheme.highContrastLight ?? committedTheme.light,
  ),
  highContrastDarkTheme: decodeTheme(
    committedTheme.highContrastDark ?? committedTheme.dark,
  ),
  themeMode: decodeMode(committedTheme.mode),
  home: EnvironmentReporter(child: BonsaiFlutterView(...)),
)
```

All `ThemeData` construction should live in one renderer module with exhaustive
typed mapping. The existing `_buildTheme` path should call the same decoder for
subtree themes rather than maintaining a smaller constructor.

The generated managed host should pass `BonsaiFlutterRoot` directly to
`BonsaiFlutterHostAdapter.buildHost`; it should no longer create an outer
`MaterialApp`. Custom hosts, examples, integration harnesses, and package tests
must make the same migration. Adapter documentation should state that adapters
may install plugin, lifecycle, localization-service, and dependency scopes but
do not own application `ThemeData`.

An adapter can technically wrap the application in another Flutter `Theme`,
but the inner `MaterialApp` will install the authoritative OCaml theme for its
application subtree. Native widgets may still install documented local themes
inside their own renderer-owned subtree; that does not change the application
theme owner.

### Define startup, failure, and replacement behavior

Before the first valid OCaml full snapshot there is no OCaml theme to decode.
The Flutter startup and pre-frame error shell therefore does not create a
default Material `ThemeData` or display Material-themed loading UI. It can
render a minimal `WidgetsApp`, `Directionality`, or application-independent
platform surface.

After the first commit, loading transitions, recoverable errors, and fatal
diagnostics should retain the last committed OCaml application theme while the
runtime remains the same. Runtime replacement clears the old theme and waits
for the replacement runtime's full snapshot, preventing one application's
theme from leaking into another runtime epoch.

A build-time bootstrap theme is intentionally excluded. It would duplicate
theme input outside the live OCaml render result and weaken the single-owner
guarantee.

## Decision

Adopt `Theme.data`, `Theme.application`, and `App.View.t` as the application
theme contract. Every maintained application supplies required light and dark
theme data with its logical body. Protocol 1.21 carries that value in one
`Set_application_theme` operation outside the logical node tree, while local
`Ui.Widget.theme` remains a subtree override using the same structured
`Theme.data` codec.

`BonsaiFlutterRoot` owns the single framework `MaterialApp` after the first
valid theme and widget-tree transaction commits. It uses one centralized,
exhaustive Material 3 decoder, reuses supplied normal variants when optional
high-contrast variants are absent, and caches decoded theme objects until the
serialized value changes. Managed and custom hosts do not provide an outer
`MaterialApp` or application `ThemeData`.

## Alternatives considered

### Only add more fields to the existing Theme node

This is the smallest protocol change, but the node remains below the generated
`MaterialApp`. It cannot configure `MaterialApp.themeMode`, app-level high
contrast variants, startup shell theme, or framework overlays above the node.
It improves subtree styling without satisfying application ownership.

### Keep MaterialApp outside and publish theme through a Dart callback

`BonsaiFlutterRoot` could send decoded theme changes to a generated stateful
host, which then rebuilds the outer `MaterialApp`. This introduces a second
mutable state channel outside `NodeStore`, separates theme publication from
frame commit, complicates runtime replacement, and allows the widget tree and
theme to become temporarily inconsistent.

### Add a MaterialApplication logical widget node

A root-only logical node could render `MaterialApp` and contain the application
body. This makes ownership visible in the widget tree, but an application shell
is not a repeatable widget: it must occur exactly once, cannot be keyed or moved,
and has lifecycle rules that differ from normal reconciliation. App-scoped
frame state expresses those invariants more directly.

### Put a static theme argument on App.create

`App.create ~theme` would be easy to encode during startup, but the theme could
not react to application state, user preference, or OCaml-observed environment
changes. A reactive `App.View.t` keeps state ownership in Bonsai and makes theme
and body updates atomic.

### Serialize every Flutter ThemeData and component-theme field

This maximizes immediate configurability but exposes Flutter class structure,
deprecated fields, state-property rules, and SDK churn through the OCaml API.
It also makes cross-renderer meaning unclear. Renderer-neutral seed color,
typography, shape, and density tokens provide a smaller stable contract.

### Allow the host adapter to provide a base ThemeData

The renderer could apply OCaml overrides with `ThemeData.copyWith`, but the
result would have two owners and would depend on hidden Dart defaults. It would
also make identical OCaml values render differently across applications. This
does not meet the requested guarantee.

### Send the theme as JSON or an opaque native-widget payload

This avoids schema work but gives up generated IDs, bounded typed decoding,
cross-language fixtures, readable debug output, and malformed-input rejection.
Application theme is core protocol state and should remain typed.

## Consequences

- Application components return `App.View.t`; the widget-only `App.create`
  path no longer exists.
- Application theme changes are reactive and commit atomically with logical
  node changes. Unrelated frames retain decoded theme identity.
- Startup and pre-frame failures use a minimal non-Material surface. Runtime
  replacement clears the prior epoch's theme before the replacement starts.
- The wire format and both decoders now carry and validate the complete core
  token model, increasing codec and fixture size.
- Font names select host-bundled assets but do not package those assets.
- The renderer remains intentionally unable to accept system dynamic colors,
  raw Flutter theme objects, semantic role records, or per-component theme
  objects through this first-release API.

## Acceptance criteria

- The final proposal precisely defines `Theme.data`, `Theme.application`, the
  application render result, and the first-release seed color, Material
  typography, shape, density, and tap-target configuration groups.
- Every maintained `App.create` and `App.create_with_worker` component returns
  an explicit application theme together with its logical body; no implicit
  default-theme compatibility path remains.
- The managed generator, custom-host documentation, examples, tests, and
  adapters no longer place a Flutter-owned `MaterialApp` around
  `BonsaiFlutterRoot`.
- Exactly one framework-owned `MaterialApp` is built after an OCaml application
  theme has committed, and all of its light, dark, and high-contrast
  `ThemeData` values are decoded from that OCaml value.
- `useMaterial3` is explicitly true, and no application theme comes from
  `ThemeData()` defaults, an adapter-supplied base theme, or a compatibility
  fallback.
- Theme mode and high-contrast selection happen immediately in Flutter and use
  only OCaml-supplied variants. Missing high-contrast variants reuse the
  corresponding supplied normal variant.
- Application-theme and widget-tree changes validate and commit atomically in
  both the OCaml driver and Dart `NodeStore`.
- Local `Ui.Widget.theme` uses the same expanded `Theme.data` mapping and is
  documented as a subtree override rather than an application owner.
- Seed colors, dynamic variants, contrast, typography roles, font names, shape
  values, density, and tap targets have typed OCaml constructors and symmetric
  OCaml/Dart boundary validation.
- Explicit semantic color-role records, system dynamic colors, and
  per-component themes are absent from the first-release public and wire
  surfaces.
- Protocol schema generation, cross-language fixtures, malformed-theme tests,
  app-shell widget tests, dynamic mode tests, high-contrast tests, runtime
  replacement tests, public API tests, Gallery coverage, and documentation are
  included in the eventual implementation plan.
- Tests prove that unrelated widget frames do not recreate theme state, a
  theme-only frame updates the one `MaterialApp`, and runtime replacement never
  reuses the previous epoch's theme.
- Startup and pre-frame failure behavior is explicitly documented and never
  creates an unowned default Material `ThemeData`.

## Risks

- Moving `MaterialApp` inside `BonsaiFlutterRoot` changes the public hosting
  contract and requires coordinated migration of every example, custom host,
  integration test, and adapter.
- A complete Material typography and shape-token surface will substantially
  increase protocol, equality, validation, and fixture code.
- Seed-generated schemes can change with the pinned Flutter SDK even when the
  OCaml seed is stable. The selected compact API accepts that version-pinned
  rendering trade-off.
- Font names do not guarantee that corresponding font assets are bundled in the
  Flutter host. Incorrect names may silently fall back unless tests or host
  packaging checks detect the problem.
- Shape mapping can accidentally diverge from Material 3 semantics. Future
  component tokens could become a Flutter API mirror if additions are not
  use-case driven.
- Delaying `MaterialApp` until the first snapshot means pre-frame loading and
  startup failures cannot use branded Material widgets under the strict
  ownership guarantee.
- Rebuilding `MaterialApp` for theme changes may disturb Navigator,
  ScaffoldMessenger, focus, restoration, or renderer resources unless its key
  and state identity remain stable and tests cover each lifecycle.
- Flutter-local system colors would make the rendered color scheme depend on
  platform state not serialized by OCaml, weakening deterministic ownership.
- High-contrast and system brightness can change while a frame is in flight;
  theme selection and environment reporting must avoid feedback loops or
  temporarily mismatched variants.

## Questions

No open questions remain. The exploration resolved the original questions as
follows:

1. The first release supports only the renderer-neutral core: seed-generated
   `ColorScheme`, full Material typography, shape scale, density, and tap
   targets. Per-component themes require a later evidence-backed decision.
2. No Material-themed loading UI is displayed before the first OCaml full
   snapshot. No separate bootstrap theme is introduced.
3. Flutter immediately selects among OCaml-supplied light, dark, and
   high-contrast variants in `System` mode without an OCaml round-trip.
4. The first release supports seed-generated `ColorScheme` values rather than
   an explicit complete semantic color-role record.
5. System dynamic colors are not supported, preserving deterministic OCaml
   ownership.
6. `Ui.Widget.theme` remains available, uses the same expanded `Theme.data`,
   and is explicitly limited to subtree overrides.
