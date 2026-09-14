# Native URL host service

The SwiftUI host implements the existing typed `Host_effect.open_url` request.
The Host Effects example owns an editable URL and its asynchronous result in
OCaml. SwiftUI presents the native URL field and Open URL button; the field's Go
submission uses the same OCaml action.

## Wire and native execution

Host request kind 3 contains one length-prefixed UTF-8 URL string. Framing,
transfer limits, request identity and trailing-byte validation are part of the
atomic frame transaction. A syntactically framed request containing an invalid
URL reaches the service and returns an error instead of invalidating unrelated
view changes. The service requires an absolute URL with a scheme and enforces
the existing 1 MiB transfer limit. Foundation supplies URL parsing; no shell
command, browser script or Flutter URL adapter executes the request.

On macOS, the service calls the asynchronous
[NSWorkspace URL opening API](https://developer.apple.com/documentation/appkit/nsworkspace).
Launch Services chooses the registered handler. Native failure is delivered to
the OCaml request instead of presenting an additional system error/authentication
panel (`promptsUserIfNeeded` is false; this does not suppress Gatekeeper).
On iOS, the service uses
[UIApplication.open](https://developer.apple.com/documentation/uikit/uiapplication/open(_:options:completionhandler:)).
A false result becomes a failed host response. Successful execution returns the
empty unit payload expected by OCaml. Success establishes native acceptance;
it does not assert that a web page loaded or an external application's work
completed.

## Activity, cancellation and lifetime

URL requests share the existing host dispatcher: execution requires an accepted
presentation while the session is active and visible. Unknown handlers and
native errors become bounded error responses. The service checks cancellation
before native dispatch and again after native completion.

Cancellation before dispatch prevents opening the URL. A request/cancel pair
in the same batch never launches an application. Once the OS has accepted a
request, cancellation cannot undo delivery or close an external application;
the caller receives cancellation and late success/error replies are fenced by
the pending-operation identity. Session reset suppresses replies and requests
from the closed lifetime. No default application preference is changed.

## Real application evidence

`URLHostServiceTests` builds and ad-hoc signs a small native URL receiver with a
unique bundle identifier and custom scheme. Launch Services resolves that App,
and its NSApplication delegate records the actual received URLs. The test
checks two ordered deliveries with percent-encoded Unicode, invalid/relative
URLs, an unregistered scheme, cancellation before dispatch and suppression of
late replies after real native delivery. The receiver does not activate a UI.
Each fixture unregisters its own App and removes its files after testing.

The receiver lives under `_build/validation/url-receivers/`. Registration in the
system temporary directory did not yield a resolvable handler in this environment;
using the normal application build location and waiting for an actual
Launch Services lookup resolves that test setup issue. Production URL dispatch
is not replaced or injected by the test.

The production Host Effects native window test edits the real NSTextField,
presses Open URL, verifies no launch while inactive, resumes, observes the exact
URL in the receiver and reads the successful OCaml status. A relative URL yields
the OCaml error status, and closing the session before another request dispatch
prevents an additional delivery. Clipboard, platform information and window
services remain covered by that same native scenario.

Initial tests reproduce unsupported request decoding and the absent URL field
(`/tmp/swiftui-url-host-red-final.log` and
`/tmp/swiftui-url-host-window-red.log`). The earlier WireReader argument-label
compilation error was a corrected test setup error, not a production failure.
After implementation and receiver setup correction, all 15 related tests pass
in five suites in 1.994 seconds
(`/tmp/swiftui-url-host-receiver-location.log`). The actual OCaml/native window
scenario passes in 28.556 seconds (`/tmp/swiftui-url-host-window-green.log`).
The OCaml `@all @runtest @fmt` gate passes
(`/tmp/swiftui-url-host-ocaml-green.log`).

Physical-iOS URL dispatch and foreground activation behavior remain unverified.
Compilation, macOS native receipt and the existing signed-iOS build checkpoint
do not establish those device behaviors. Full Mail window screenshots and all
other unfinished migration requirements remain separate acceptance work.


The full Swift gate passes 380 tests in 85 suites in 330.458 seconds with a
fresh completed xUnit report (`/tmp/swiftui-url-host-full.log`). All three
platform gates pass in 18.554 seconds (`/tmp/swiftui-url-host-platforms.log`),
including compilation of the complete module and ten Swift entrypoints for
physical iOS 18, plus explicit Simulator/Intel rejection. Strict formatting
of the changed Swift sources, whitespace checks and all 49 decision-document
checks pass; protected spec files are unchanged. Device URL dispatch and full
Mail screenshots remain unverified.


Host Effects and Mail were rebuilt through the native CLI as macOS Debug and
signed physical-iOS Release Apps. Host Effects' changed OCaml program was
cross-built again for iOS 18 (`/tmp/swiftui-url-host-ios-object.log`). All four
bundles pass architecture, minimum-version, metadata and deep/strict signature
checks (`/tmp/swiftui-url-host-bundle-audit-final.log`). The iOS Apps retain
iPhone/iPad families and embedded provisioning profiles. Their current hashes
and source checkpoint are in `_build/validation/swiftui-url-host-bundles.json`;
the iOS example manifest refreshes these two records and leaves the other eight
at their recorded earlier checkpoints. Mail's macOS CLI identity record is
also refreshed.

The final artifact check exposed test-only receiver cleanup skipped by the
native window process's direct `exit` call. The success path now closes the
fixture explicitly before exiting; the window scenario passes again in 28.786
seconds (`/tmp/swiftui-url-host-window-final.log`) and the receiver directory is
empty afterward. An earlier manual Mach-O audit invocation transposed its last
two arguments; correcting that invocation did not require a production change.
The final OCaml `@all @runtest @fmt @install` gate passes
(`/tmp/swiftui-url-host-ocaml-final.log`).

A fresh physical-device inventory still reports the paired iPhone 13 unavailable
(`/tmp/swiftui-url-host-devices.json`). No iOS installation/URL execution, full
Mail screenshot, source push or generated SDK publication occurred.
