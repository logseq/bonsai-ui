# Managed Host Async Initialization

## Problem

The generated managed host has no asynchronous application-owned
initialization phase that gates host construction. Its current startup sequence
is:

1. `main` creates a `BonsaiFlutterHostAdapter` and immediately calls `runApp`.
2. `BonsaiFlutterHost.initState` starts `_prepareRuntime`.
3. `_prepareRuntime` awaits `createApplicationPayload` and then creates the
   application platform.
4. While that future is pending, the first `FutureBuilder` build selects a
   loading child but still calls `adapter.buildHost` unconditionally.

As a result, an application-owned widget returned by `buildHost` can be
constructed before the asynchronous service it consumes is ready. Moving that
service initialization into `createApplicationPayload` does not provide an
ordering guarantee because payload preparation and host-wrapper construction
are separate branches of the first build:

```text
createApplicationPayload -> initialize dependency
buildHost                -> consume dependency
```

Logseq Journal exposed this race by mounting AWS Amplify's `Authenticator` in
`buildHost` while starting Amplify configuration in
`createApplicationPayload`. `Authenticator` was constructed before
configuration completed, remained on its loading screen, and repeatedly
reported that Amplify had not been configured. A test entrypoint that awaited
configuration before `runApp` restored the persisted Cognito session and
continued normally, isolating the failure to managed-host startup ordering.

The lifecycle gap is not specific to Amplify. Authentication SDKs, Firebase,
Sentry, encrypted storage, and other platform services may all need to finish
asynchronous setup before an application-owned host wrapper is mounted.

`createApplicationPayload` should remain responsible for the opaque native
runtime payload. Using it as an implicit host prerequisite conflates two
lifecycle concepts and still does not gate `buildHost`.

## Proposal

Add an explicit required initialization operation to the managed adapter
contract:

```dart
abstract interface class BonsaiFlutterHostAdapter {
  Future<void> prepareHost();

  Future<Uint8List> createApplicationPayload();

  BonsaiFlutterApplicationPlatform? createApplicationPlatform();

  Widget buildHost({
    required BuildContext context,
    required Widget child,
  });
}
```

The generated lifecycle must place an initialization gate before every
operation that can construct or consume application-owned host state. In
particular:

- start one `prepareHost` future for an adapter initialization attempt;
- do not call `buildHost`, `createApplicationPayload`, or
  `createApplicationPlatform` until that future succeeds;
- after success, prepare the runtime and mount the application-owned host;
- after failure, render a stable and actionable generated startup error without
  calling `buildHost` or preparing the runtime;
- allow a failed initialization to be retried without creating overlapping
  attempts; and
- never rerun successful initialization merely because the widget rebuilds.

This is a deliberate source-breaking contract change. Existing adapters must
implement `prepareHost`; adapters without asynchronous prerequisites implement
an empty method:

```dart
@override
Future<void> prepareHost() async {}
```

Do not add a default implementation or a compatibility path. Logseq Journal
can make `JournalAmplify.configure()` the sole owner of Amplify initialization
by returning it from `prepareHost` and removing the same work from
`createApplicationPayload`.

The implementation scope is expected to include:

- the public adapter interface and its contract test;
- generated managed-host source and generator source tests;
- the scaffolded adapter template; and
- every maintained example adapter and generated example `main.dart`.

The exact placement and retry ownership of the initialization gate remain open
questions. Those details must be resolved before this document transitions to
`proposed`.

## Questions

- Should the gate live in asynchronous `main` or in
  `_BonsaiFlutterHostState`? What loading and failure experience is required
  before application-owned wrappers may be mounted?
- What is the exact lifecycle unit for "exactly once": once per process, once
  per adapter instance, or once per adapter assignment to a host widget?
- When `BonsaiFlutterHost` receives a different adapter, should it initialize
  the new adapter, reject replacement after startup, or require the caller to
  provide an already initialized adapter?
- Who owns retry UI and policy? Should generated code expose a retry button,
  automatically retry, or provide a callback/state that a custom startup-error
  widget can drive?
- Does "bounded, actionable error" require a timeout for a never-completing
  future, or only a stable error state when `prepareHost` completes with an
  error? If a timeout is required, who chooses its duration?
- Is `prepareHost` permitted to depend on a `BuildContext` or application UI?
  The proposed context-free signature intentionally rules both out.
- What guarantees must an adapter provide when a failed, partially completed
  initializer is invoked again? Should retry use the same adapter instance?

## Acceptance criteria

- `BonsaiFlutterHostAdapter` exposes a required asynchronous host-initialization
  operation, and all maintained adapters implement the new contract.
- `buildHost` is not called while initialization is pending or after it fails.
- `createApplicationPayload` and `createApplicationPlatform` begin only after
  initialization succeeds.
- A successful initialization runs exactly once for the lifecycle unit chosen
  in the final decision, regardless of widget rebuilds.
- An initialization failure produces a stable, actionable error state and does
  not mount the application host or start runtime preparation.
- Retrying after failure cannot start concurrent initialization attempts.
- Generated-host tests cover pending, successful, failed, and retried
  initialization, including operation ordering and invocation counts.
- Generator source tests, the scaffold template, generated examples, and the
  adapter contract test all reflect the new lifecycle.

## Risks

- A main-level gate can leave Flutter unable to render loading or retry UI until
  initialization finishes, while a widget-level gate adds state-machine
  complexity.
- An initialization future that never completes still creates an unbounded
  loading state unless the contract defines timeout or cancellation behavior.
- Retrying a partially completed third-party SDK setup may be unsafe or
  unsupported even if the generated host serializes attempts.
- Adapter replacement in `didUpdateWidget` can accidentally rerun a globally
  scoped service initializer or allow stale futures to update the new
  adapter's state.
- Delaying runtime payload and platform creation increases time to first
  runtime frame, although it removes nondeterministic startup behavior.
- A required interface method intentionally breaks all existing managed
  adapters at compile time; every downstream application must choose whether
  its implementation is a no-op or owns real initialization.

## Alternatives considered

### Await initialization in `main` before `runApp`

Make generated `main` asynchronous, call
`WidgetsFlutterBinding.ensureInitialized`, await `prepareHost`, and call
`runApp` only after success. This gives the strongest ordering boundary and
keeps application widgets out of the tree while initialization is pending.
However, retry and failure rendering require a separate generated error app,
and the pending phase has no Flutter UI unless native launch-screen behavior is
considered sufficient.

### Gate initialization inside `BonsaiFlutterHost`

Extend the existing state-owned future so initialization completes before
runtime preparation and render a generated loading or error state outside
`buildHost`. This naturally supports loading, failure, and retry UI in one
state machine. It must be designed carefully so rebuilds, retries, and adapter
replacement cannot duplicate or overlap initialization attempts.

### Reuse `createApplicationPayload` as the initialization phase

Require applications to initialize platform services before returning the
payload. The current host already awaits this operation before constructing
`BonsaiFlutterRoot`, but it calls `buildHost` while the payload future is
pending. Changing the meaning of the payload operation would also leave host
initialization implicit and mix Dart host services with native runtime input.

### Make `buildHost` asynchronous

Change `buildHost` to return a future or make it perform initialization itself.
Widget construction is expected to be synchronous and may run repeatedly;
combining setup and construction makes exactly-once behavior, error ownership,
and retry semantics harder to express.

### Require applications to provide a custom entrypoint

Applications with asynchronous host dependencies could opt out of the managed
host and own startup ordering. This avoids changing the adapter contract but
duplicates generated lifecycle logic and defeats the purpose of the managed
adapter for a common platform-integration requirement.

## Rejection reason

Async initialization support for the managed host is deferred and will not be added at this time.
