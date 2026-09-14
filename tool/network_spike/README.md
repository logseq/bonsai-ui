# Secure Network Platform Spike

This directory contains the Phase 0 feasibility spike for the secure network
example described in
[`docs/agent-guide/013-https-websocket-example.md`](../../docs/agent-guide/013-https-websocket-example.md).
It remains the isolated platform probe while the product example is validated
in platform order: macOS arm64 first, followed by signed physical iPhoneOS
arm64.

## Scope

The spike proves that the repository's OCaml 5.1.1 and Eio 1.2 baseline can:

- initialize `Mirage_crypto_rng_unix` once;
- verify TLS certificates and DNS hostnames with `tls-eio`;
- expose a `Tls_eio.t` through a capability-safe generic stream-socket adapter;
- run HTTPS through `httpun-eio` with a 64 KiB response limit;
- run WSS through `httpun-ws` and close transports structurally; and
- cross-link the same pure OCaml stack for iPhoneOS arm64.

The checked-in certificate and private key are loopback-only test fixtures. They
must not be used by a shipped application or trusted outside these tests.

## Dependency baseline

The following exact packages resolve without changing the pinned Bonsai family:

| Package | Version |
| --- | --- |
| `ocaml` | `5.1.1` |
| `bonsai` | `v0.17.0` |
| `eio` | `1.2` |
| `tls-eio` | `2.1.2` |
| `tls` | `2.1.2` |
| `ca-certs-nss` | `3.126` |
| `mirage-crypto` family | `2.2.0` |
| `x509` | `1.1.1` |
| `digestif` | `1.3.1` |
| `httpun` | `0.2.0` |
| `httpun-eio` | `0.2.0` |
| `httpun-ws` | `0.2.0` |
| `gluten-eio` | `0.5.2` |

Verify the solver result with:

```sh
opam install --dry-run --switch=bonsai-flutter-v017-exact \
  tls-eio.2.1.2 tls.2.1.2 ca-certs-nss.3.126 \
  httpun.0.2.0 httpun-eio.0.2.0 httpun-ws.0.2.0 gluten-eio.0.5.2
```

## macOS verification

Run the deterministic loopback suite:

```sh
opam exec --switch=bonsai-flutter-v017-exact -- \
  dune runtest tool/network_spike --force
```

Run the explicit public-network smoke test separately:

```sh
opam exec --switch=bonsai-flutter-v017-exact -- \
  dune exec tool/network_spike/network_spike_cli.exe
```

The public smoke test is manual-only and must not become a CI dependency. On an
Apple Silicon macOS host, the native executable is an arm64 Mach-O. The measured
spike executable is 7,715,976 bytes and links only `libgmp` plus `libSystem`; it
does not link OpenSSL, `libssl`, `libcrypto`, or a Secure Transport wrapper.

## iPhoneOS verification

Build the complete object and probe application with:

```sh
./tool/network_spike/build_ios_device_probe.sh
```

Run the signed physical-device probe with:

```sh
./tool/network_spike/test_ios_device_probe.sh
```

The current probe complete object is an arm64 iPhoneOS object measuring
9,525,848 bytes. The product network complete object is 25,888,424 bytes. The
application closure is generated from the network example's pinned opam
metadata and Dune libraries. Package and component counts are recorded as
lock-derived metadata and recomputed by `verify_runtime_closure.sh`; they are
not fixed framework constants. Cross-compilation and native linking pass, and
the objects contain the Apple `arc4random_buf` entropy entry point but no
OpenSSL, `libssl`, `libcrypto`, or Secure Transport wrapper symbols.

The signed physical-device run completes verified loopback TLS, HTTPS,
cancellation, WSS echo, disconnect, NSS trust rejection, wrong-host rejection,
public HTTPS, and public WSS. The observed public HTTPS body was 559 bytes. The
signed product application also installs and launches on the same physical
iPhone; backgrounding and foregrounding preserve the running process without
assuming background network execution.
