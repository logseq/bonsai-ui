# ADR 0001: Upstream version baseline

- Status: Accepted
- Date: 2026-07-25
- Updated: 2026-07-30

## Context

`bonsai_flutter` needs one reproducible compiler and one aligned Jane Street
release line for host and iPhoneOS builds. The supported combination must be
available from immutable opam release metadata and must not depend on floating
preview repositories or local source pins.

The v0.17 Bonsai API differs from the later preview API in component syntax,
driver construction, state helpers, and before-display handling. Supporting
v0.17 therefore requires an explicit project-owned adapter rather than
pretending both surfaces are interchangeable.

## Decision

- Pin OCaml to 5.1.1 everywhere.
- Use Jane Street v0.17.x packages from the default opam repository.
- Resolve direct runtime packages to Bonsai v0.17.0, Incremental v0.17.0,
  Incr_dom v0.17.0, Virtual_dom v0.17.0, Core v0.17.2, and Base v0.17.3.
- Keep manifest constraints greater than or equal to v0.17 and strictly below
  v0.18.
- Use Dune 3.23.1 for the locked host and iPhoneOS environments.
- Build every Bonsai-dependent library, example, and test unconditionally.
- Use `Bonsai.Cont` and the project-owned `Bonsai_v017.state` helper.
- Use public `Bonsai_driver` operations for creation, flushing, result access,
  event scheduling, lifecycle triggering, and observer invalidation.
- Implement before-display waiting in the project driver because the v0.17
  driver does not expose the later helper.
- Build the iPhoneOS runtime closure from the same OCaml and Jane Street
  release line as the host.
- Keep Flutter 3.44.8, Dart 3.12.2, and the `package_ffi` build-hook model.

## Consequences

The repository has one OCaml build graph and one release family. A missing or
misaligned dependency is a build error rather than a reason to omit runtime
libraries or tests.

Patch releases inside the Jane Street v0.17 train are permitted and recorded;
the repository does not require every package to share an identical patch
number.

The exact compiler pin favors reproducibility. Moving the compiler or Jane
Street release family requires passing the complete OCaml, Flutter FFI,
macOS, and iPhoneOS gates.

`virtual_dom.ui_effect` and selected Incr_dom runtime components remain
transitive implementation dependencies. No DOM view type crosses the
`bonsai_flutter` public UI boundary.
