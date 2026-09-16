# Shared UI Defaults

The [Theme-owned defaults decision](../../implemented/architecture/2026-09-15-ocaml-owned-ui-defaults.md)
supersedes this decision's JSON source and fixed text/symbol defaults. This
record retains the initial implementation and acceptance history.

## Problem

Note repeats icon sizes, minimum control bounds, text styles, colors, spacing,
corners, and material recipes in application code. Other applications must
currently reproduce those choices to obtain the same baseline appearance.
Small differences, such as 17/19/22-point action icons and 0.6/0.7-point borders,
also accumulate without a shared default policy.

On September 15, 2026, the user clarified that the desired outcome is shared
default configuration, illustrated by using one recommended size for ordinary
icons. The user then requested an exploring document for icon size, hit targets,
text roles, theme color roles, common spacing, and corner/material presets.
This document covers that configuration contract. It does not propose a new
catalog of application components. The user authorized implementation on
September 15, 2026.

### Baseline evidence

- [Note](../../../../examples/note/ocaml/note.ml) defines a 19-point `symbol`
  helper, 44-point button/menu bounds, a 17-point `label` helper, leading columns
  with 16-point spacing, warm/cool palettes, and repeated `glass` surface settings.
  Search and close controls also specify separate icon sizes.
- [View](../../../../ocaml/ui/view.ml) leaves symbol size/color optional, defaults
  buttons to Automatic, and leaves ordinary row/column spacing optional.
  Adopting explicit library defaults changes observable behavior; this is a
  feature decision rather than a behavior-preserving simplification.
- [Theme](../../../../ocaml/ui/theme.mli) exposed mode, tint, font
  family, and control size at the baseline. It did not expose semantic text/color roles or
  the spacing and surface recipes proposed here.
- [Surface](../../../../ocaml/ui/native_widget.mli) already supports gradients,
  materials, background opacity, corners, borders, and shadows. New presets
  should use this shared capability rather than introduce another paint path.
- [Note acceptance](../../../swiftui-note.md) records material, input, layout,
  and accessibility evidence. The user explicitly chose to retain native sheet
  keyboard avoidance and iOS 26 full-height opacity behavior.
- The [Note decision](../../implemented/feature/2026-09-15-note-example.md)
  owns the example. This decision owns subsequent shared defaults. The active
  [SwiftUI backend decision](../../proposed/architecture/2026-09-11-swiftui-only-apple-backend.md)
  remains authoritative for platform architecture; no alternate backend is added.

## Proposal

### One shared default configuration

Make existing primitives and their styles resolve omitted configuration through
one shared set of defaults. Applications should not need Note-specific wrappers
to obtain ordinary icon sizes, foreground colors, or spacing. Explicit arguments
continue to express intentional exceptions.

Use the existing Theme/Style public surface where practical. Exact type names
and wire representation remain implementation design work. Avoid a parallel
theme system, a generic string-keyed property registry, or new wrapper components
whose only purpose is to supply constants.

Resolution order is explicit component property, nearest applicable theme/style
override, then the library default. A nested scope overrides only supplied
properties. Semantic system colors and font behavior remain native where
appropriate. Keep one source of truth rather than independent OCaml and Swift
copies of the same defaults.

### Icons and interactive bounds

| Setting | Proposed default | Scope |
| --- | --- | --- |
| Ordinary symbol size | 19 points | All ordinary action icons, including button, menu, search, clear, and close icons |
| Symbol rendering | Monochrome | Preserve explicit rendering overrides |
| Symbol foreground | Inherited primary foreground role | Secondary icons explicitly select the secondary role |
| Icon button/menu minimum target | 44 by 44 points on iOS/iPadOS only | Minimum interactive bounds, not a 44-point glyph; macOS retains native control sizing |
| Interactive row minimum height | 44 points on iOS/iPadOS only | Native controls and custom actionable rows; macOS retains native control sizing |
| Icon alignment | Center within its target | The target must include its visible padding |

The 19-point value is a project recommendation derived from Note, not a claim
that Apple mandates this size. Small disclosure indicators and prominent
decorative icons may explicitly override it. Preserve native control-size
choices; do not silently defeat an explicit compact configuration. Keep existing
Button Automatic styling unless a caller deliberately chooses Plain.

The user confirmed on September 15, 2026 that the 44-point minimum applies only
to iOS/iPadOS. Do not apply this minimum to macOS; retain its native control-size
behavior. This platform choice is settled.

### Text roles

| Role | Proposed base size and weight |
| --- | --- |
| Body | 17 points, Normal |
| Page title | 24 points, Bold |
| Sheet title | 19 points, Medium |
| Editor/preview title | 22 points, Bold |
| Empty-state title | 20 points, Bold |
| Caption | 14 points, Normal |
| Hint | 13 points, Normal, secondary foreground |
| Section label | 12 points, Normal, secondary foreground |

Use the system font by default. Base sizes must retain Dynamic Type and system
legibility settings rather than become fixed accessibility-insensitive fonts.
Italic is an explicit hint-style option. Note's additional 4-point line spacing
belongs to an optional reading-body style, not every label or native text field.
Miniature mock document text remains an explicit Note override.

### Theme color roles

Provide shared roles for primary foreground, secondary foreground, page
background, card background, inset section background, search background,
border, shadow, and material tint. Icons inherit foreground roles instead of
maintaining a duplicate icon palette. Components may override their particular
border/shadow/tint recipe.

Default semantic roles should adapt to platform appearance and accessibility.
Keep Note's warm/cool RGB palettes as application overrides. Do not make brown
text, cream paper, or forced Light mode the library-wide default. Keep the
existing tint meaning for controls distinct from decorative material tint.

### Spacing and corner defaults

| Setting | Proposed value or rule |
| --- | --- |
| Ordinary content column spacing | 16 points |
| Common spacing scale | 4, 8, 12, 16, 24, 32 points |
| Page/editor content inset | 16 points when that style is selected |
| Compact action-group spacing | 2 points |
| Compact action-group inset | 6 points horizontally, 2 points vertically |
| Small surface/image corner | 8 points |
| Search-surface corner | 10 points |
| Content-card corner | 20 points |
| Custom sheet-surface corner | 28 points |
| Capsule shape | Derived from container height, not a fixed 30-point radius |
| Fine decorative border | 0.7 points in the relevant surface recipes |

These are named defaults and opt-in styles, not implicit padding on every
primitive. Preserve deliberate zero spacing, native divider appearance, row
alignment, and explicit layout constraints. Note's 14/18-point gaps can remain
overrides where necessary; do not quantize all existing layouts automatically.
Numeric defaults require layout evidence as part of implementation acceptance.

### Surface recipes

| Recipe | Proposed settings |
| --- | --- |
| Plain Surface | Background opacity 1; no automatic decorative border or shadow |
| Material action group | Thin material; theme tint; capsule; 0.7-point border; shadow radius 14, x 0, y 6 |
| Content card | 20-point corner; theme card background; optional fine border |
| Inset section | 8-point corner; theme inset background |
| Translucent sheet surface | Ultra thin material; tint alpha 0; background opacity 0.4; 28-point corner; optional fine border |

Recipes must keep text and controls fully opaque. Under Reduce Transparency,
material paint uses its opaque RGB color and opacity 1, as Surface already does.
Allow theme-specific border and shadow colors/alpha. Note's white borders and
brown shadow are overrides, not universal colors.

The translucent recipe customizes paint only. It must not select Fraction 0.98,
change presentation sizing, disable native keyboard avoidance, or force a
full-height sheet to remain transparent. Preserve the user's decision to follow
standard SwiftUI presentation behavior.

### Adoption and boundaries

- First use Note to demonstrate omitted ordinary configuration and explicit
  exceptions. Remove redundant Note helpers and literals only after their
  policy is supplied by the shared implementation.
- Audit other supported consumers of changed primitive defaults, especially
  Mail, Gallery, and standalone examples. Their layouts may change when a
  previously inherited default becomes explicit; make intentional exceptions
  explicit and verify affected views.
- Do not add SearchField, Card, Toolbar, or page-shell abstractions in this
  decision. Additional components require independent justification.
- Keep business state, event handlers, accessibility names, input byte limits,
  fixed grid column counts, cover heights, and fixture assets in applications.
- Do not preserve obsolete default paths with compatibility modes, aliases, or
  migrations. If wire changes are necessary, update the schema, generators,
  decoders, and supported consumers together.
- Do not change protected OCaml spec files or Dune files under this decision's
  current authorization. If a protected contract blocks implementation, report
  the specific issue before proceeding. Any future source commit/push must
  follow the separate iOS SDK publication requirement.

### Implementation design

- `Theme.Defaults` carries fixed typed sparse overrides for metrics, text roles,
  color roles and foreground selection. Native environment merging preserves
  unspecified values. Omitted control size now inherits instead of resetting to
  Regular.
- `Style.Text_role` and `Style.Color_role` provide semantic selectors. Text style
  accepts role, foreground and italic alongside existing explicit properties.
- `protocol/ui-defaults.json` owns numeric baseline values; the generator emits
  OCaml named constants and Swift renderer constants. Native semantic colors
  remain platform-owned.
- Protocol 7 transports the fixed sparse configuration and text-role selection.
  Surface version 3 adds recipe/shape flags and an explicit-property mask to its
  existing paint payload. Old protocol/Surface payloads are rejected.
- Surface recipes supply paint and opt-in insets; the action-group recipe also
  supplies descendant row spacing. Native bounds participate in iOS layout and
  label hit testing, with compact control-size exceptions and no macOS minimum.
- Note adopts semantic roles, shared action-group/card/inset/search/sheet recipes
  and ordinary icon sizing while retaining its palette, document fixtures and
  native presentation configuration.

## Decision

The shared Theme/Style defaults and Surface recipes are implemented and adopted
by Note. [Public configuration](../../../theme.md) documents typed overrides,
inheritance, accessibility and platform scope. [Acceptance evidence](../../../shared-ui-defaults-acceptance.md)
records regression tests, real macOS windows, physical-iOS interaction checks,
before/after captures and source hashes.

Validation passes: OCaml build/tests, all 537 Swift tests in 111 suites, protocol
generation and fixture checks, native runtime/platform checks, all four standalone
CLI tests covering 12 example builds, Note/Mail macOS windows, and all eight
physical-iPhone acceptance groups.

## Alternatives considered

### Keep all choices in Note helpers

This preserves current primitive behavior and minimizes library changes, but
leaves every application responsible for duplicating the same ordinary defaults.
It does not satisfy the user's requested shared configuration.

### Leave every omitted value to SwiftUI

Native inheritance has value and remains appropriate for colors, accessibility,
and presentation behavior. It does not establish the requested consistent
19-point project icon default or reusable custom material recipes by itself.

### Copy the complete Note appearance into global defaults

This would spread fixed light colors, highly transparent sheets, miniature text,
and document-specific dimensions across unrelated applications. Keep those as
explicit styles or application choices instead.

### Introduce a separate component library

A new catalog of wrapper components could collect these constants, but it would
expand the scope beyond default configuration. Prefer existing primitives and
one shared theme/style contract first.

## Acceptance criteria

- Ordinary symbols without an explicit size use the same 19-point default in
  buttons, menus, and search/close compositions. An explicit size still wins.
- Root and nested style overrides follow the documented resolution order,
  preserve unspecified values, and update existing views without replacing
  input controllers, losing focus, or resetting application state.
- Interactive bounds are verified at a minimum of 44 points on iOS/iPadOS,
  while macOS retains native control-size behavior without this minimum.
  Padding participates in hit testing, and neighboring controls do not gain
  overlapping hit targets.
- Text roles scale with Dynamic Type, respect Bold Text and layout direction,
  and remain readable in narrow layouts. Color roles respond to light/dark
  appearance without importing Note's fixed palette globally.
- Surface recipes use the existing native paint implementation, preserve child
  opacity and accessibility, and become opaque under Reduce Transparency.
- Native sheet keyboard expansion and full-height opacity remain unchanged;
  leaving search restores the normal material state as in Note's acceptance.
- Note removes ordinary repeated size/style constants and retains only deliberate
  exceptions. Review before/after physical-iOS and macOS captures; do not assume
  the proposed normalized sizes preserve every existing pixel.
- Verify impacted Mail/Gallery/example views and run focused native behavior
  tests, OCaml tests, and protocol fixture checks where representation changes.
  Do not add tests that merely duplicate a table of constants.
- Document public defaults, platform scope, override precedence, recipes, and
  accessibility behavior. Validate all decision documents before completion.

## Consequences

Note removes 47 numeric configuration occurrences from the eight measured
categories (60 to 13, a 78.3% reduction) and five local policy helpers. It selects
15 semantic text roles and eight surface recipes. Total source length increases
from 983 to 1009 lines because typed style selection and scoped palette setup
add lines; this is a reduction in duplicated configuration, not total lines.

Protocol 7 and Surface version 3 replace the prior payload layouts. No protected
OCaml spec or Dune files are changed. No source commit or push is included; the
separate iOS SDK publication requirement remains applicable after a future push.

## Risks

- Explicit defaults can change layout for callers that previously inherited
  system sizing. This is intentional API behavior to review, not a transparent
  refactor or a reason to add a legacy switch.
- Applying the 44-point minimum through shared layout code could accidentally
  enlarge desktop toolbars. Verify that it is limited to iOS/iPadOS and does not
  override native macOS control sizing.
- Resolving defaults too early can break nested inheritance or make runtime
  theme changes require reconstructing views. Resolving them independently in
  both languages creates divergent sources of truth.
- A large set of tokens can become as cumbersome as repeated constants. Limit
  the first API to the six families requested here and avoid a general styling
  framework.
- The translucent sheet recipe can expose distracting background text. Keep it
  opt-in and retain opaque/material alternatives and accessibility behavior.

## Questions

No open questions. The user confirmed that the 44-point minimum applies only to
iOS/iPadOS; macOS retains native control sizing. The user requested transition
to proposed and subsequently authorized implementation on September 15, 2026.

