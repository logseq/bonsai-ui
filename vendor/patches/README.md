# Upstream patches

The active dependency graph uses OCaml 5.1.1 and the Jane Street v0.17.x
release line. It does not build `basement`.

The repository retains the earlier macOS portability patch in
[`basement-macos.patch`](basement-macos.patch):

- use the public `Caml_state` runtime macro;
- prevent OCaml's internal `fallthrough` macro from expanding inside Apple's
  dispatch headers.

It is inactive and retained only as provenance for the previous baseline.

## iOS target patches

`ios/jst-config-host-discover.patch` applies to the locked `jst-config`
v0.17.0 archive. The upstream rule aliases
`discover.exe` through a named dependency and then executes `%{first_dep}`.
Dune 3.23 cannot recognize that indirection as a host tool while building an
`ios` context, so it attempts to link and run an iOS executable during the
build.

The patch expresses the same dependency directly in the `run` action. Dune's
cross-compilation rule then selects the native host executable, while
`dune-configurator` receives the target context and probes with the iOS
compiler. The generated `config.h` behavior is unchanged except that it now
describes the intended Apple target.

Remove this patch when upstream invokes the discovery executable directly or
when Dune recognizes executable aliases in cross-context actions.

`ios/base-host-generator.patch` changes the Base v0.17 generator action from
the target-context `%{ocaml}` executable to the native host `ocaml`
executable. Generated source is unchanged; only the executable context is
selected explicitly.
