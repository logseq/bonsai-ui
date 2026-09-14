# Application themes

OCaml is the sole owner of application theme data. Every application component
returns an `App.View.t` that pairs a reactive `Theme.application` with its
logical widget body:

```ocaml
let color_scheme =
  Ui.Theme.Color_scheme.from_seed
    ~color:(Ui.Style.Color.rgb ~red:103 ~green:80 ~blue:164)
    ~variant:Ui.Theme.Color_scheme.Tonal_spot
    ~contrast_level:0.
    ()
in
let light =
  Ui.Theme.material
    ~brightness:Ui.Style.Brightness.Light
    ~color_scheme
    ()
in
let dark =
  Ui.Theme.material
    ~brightness:Ui.Style.Brightness.Dark
    ~color_scheme
    ()
in
let theme =
  Ui.Theme.application ~mode:Ui.Theme.System ~light ~dark ()
in
App.View.create ~theme ~body:(Ui.View.Body.static body)
```

`Theme.data` describes one complete renderer input. Its initial stable token
surface contains a seed-generated color scheme, dynamic-scheme variant,
contrast level, all Material 3 typography roles, font family and fallback
names, five shape radii, visual density, and tap-target policy. Contrast must
be finite and in `[-1, 1]`; shape radii must be finite and non-negative. Font
names must be non-empty and contain no NUL, and at most sixteen fallback names
are accepted.

`Theme.application` requires light and dark data and selects them with
`System`, `Light`, or `Dark`. Optional high-contrast light and dark data must
have matching brightness. When omitted, Flutter reuses the corresponding
decoded normal theme; it does not construct a default. System brightness and
high-contrast selection happen immediately in Flutter without changing OCaml
ownership. Material 3 is always enabled.

`Ui.Widget.theme ~data` is a deliberate subtree override. It uses the same
`Theme.data` decoder but cannot change application mode or the
framework-owned `MaterialApp`.

Font family names select assets already bundled by the Flutter host. They do
not package fonts. Add each referenced family and weight to the host's
`pubspec.yaml`; otherwise Flutter may use a platform fallback.

The initial API intentionally excludes semantic color-role records, system
dynamic colors, per-component theme objects, `ThemeExtension`, raw Dart theme
payloads, and Flutter `WidgetStateProperty` values. Component defaults are a
fixed renderer mapping from the serialized core tokens.

Before the first valid full snapshot, `BonsaiSwiftUIRoot` renders only a
minimal non-Material startup or error surface. After commit, it retains the
last theme for same-runtime errors. Replacing the runtime clears the old theme
immediately and waits for the replacement epoch's full snapshot.
