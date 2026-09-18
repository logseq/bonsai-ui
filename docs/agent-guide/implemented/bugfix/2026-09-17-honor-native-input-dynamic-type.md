# Honor Native Input Dynamic Type

## Problem

Physical Journal acceptance at the largest UIWindow content-size trait enlarges
native titles and forms, but Capture editor text remains near its normal size.
NativeTextEditorView and NativeTextFieldView assign a body font during SwiftUI
updates. The UIKit SharedUIDefaults helper scales without the input's effective
content-size category. A later assignment can therefore undo local trait scaling.

## Decision

First reproduce with actual SDK UIKit input views hosted in SwiftUI. Exercise
normal, maximum accessibility, smaller and restored sizes while retaining the
same editor/field controller. Include plain and secure fields, Bold Text and a
focused editor with marked text. Assert actual UIFont point sizes and retained
native text/selection/composition/focus. If confirmed, resolve fonts using the
inherited SwiftUI Dynamic Type category through UIKit's explicit compatible trait
parameter. Preserve theme base size and family. The same native test also confirms that a
Courier family ignores a numeric bold weight descriptor; select its native bold
face when Bold Text requests it, preserving other symbolic font traits.

## Ownership and test boundary

OCaml text reducers and Swift TextSession own text, revisions and selection, not
UIFont or the SwiftUI dynamicTypeSize environment. Their public events have no
font-category input and their state/effects cannot produce this defect. Do not
inject an already incorrect font as a fake reducer result. The narrow executing
boundary is the UIKit representable and UIFontMetrics helper; use hosted native
XCTest for it, without full OCaml sessions, storage or transport regression tests.
Physical Journal rechecking is acceptance evidence, not duplicate regression.

## Alternatives considered

### Set a larger fixed editor size in Journal

Rejected: this would ignore semantic scaling and leave other native inputs wrong.

### Rely only on adjustsFontForContentSizeCategory

Rejected if the reproduction confirms subsequent SwiftUI updates overwrite the
trait-scaled font. The assigned font must respect the effective environment.

## Acceptance criteria

- Hosted UIKit regression fails on actual font size before implementation.
- The same native inputs track increasing and decreasing inherited size changes.
- Theme defaults and Bold Text remain effective; secure entry stays secure.
- Focus, text, selection and marked composition survive style changes.
- Relevant SDK native tests and physical Journal acceptance pass after repair.
- No OCaml, Dune or protected spec edits, compatibility paths or production graph
  mutations occur. Record installed SDK and app artifact provenance.

## Consequences

The deterministic UIKit reproduction fails before implementation on actual font
sizes and Courier Bold Text. The final hosted test passes system and custom fonts
through normal, accessibility5, small, accessibility3 and restored sizes, with both
legibility values and retained text, selection, marked range, focus and secure
entry. An empty custom inputView isolates synthetic marked text from asynchronous
system keyboard candidate updates. Real keyboard interaction is separately
verified in the consuming app, not duplicated as a font regression.

The UIKit body-font helper takes the inherited DynamicTypeSize explicitly. System
body text uses the native preferred font for that category; custom family/size
uses compatible UIFontMetrics. Bold weight selects the corresponding native face.
Both editor and field representables provide their SwiftUI environment size.

The 27 related macOS SDK tests pass. Updated local SDK sources rebuild the actual
Journal Release app and isolated host. Three physical application acceptance cases
pass together: maximum-size navigation/composer input, actual Pinyin candidate
composition through Task/rotation, and production cold-start Capture/rotation.
Screenshots confirm that previously small editor text now enlarges and reflows.
No production graph or global preference is mutated. All failures, corrected test
oracles, source hashes, binaries and final runs are retained in the consuming
Journal repository's batch 38 implementation ledger. No commit, push or SDK
release is performed. The full Journal UI standardization goal remains open for
other accessibility, recovery and performance requirements.

## Risks

- Applying UIKit automatic scaling to an already resolved font could scale twice;
  assert actual point sizes across repeated changes rather than visual growth alone.
- Window traits and SwiftUI environment overrides have distinct propagation; use
  the value inherited at the actual representable boundary.

## Questions

- None. This repairs the native typography requirement exposed by iPhone acceptance.
