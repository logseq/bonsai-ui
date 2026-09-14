# Embedded Apple Worker

The Worker runs an Eio event loop in its dedicated OCaml Domain. Services retain
network, filesystem, clock, random-source, standard-stream, debug and domain
capabilities. `Worker.environment` names `Worker_eio_backend.environment`; it no
longer exposes a subprocess manager. Process creation is outside this embedded
Apple service environment.

## Signal ownership

The application owns its process-wide signal dispositions. Starting, reusing or
closing a Worker must not install an OCaml SIGCHLD handler in the SwiftUI host.
The command-line `Eio_posix.run` entrypoint installs such a handler. In the pinned
OCaml 5.1 runtime, signal recording accesses the receiving thread's OCaml domain
state, which a foreign Swift/AppKit thread does not have. A native regression
reproduced a SIGSEGV when delivering SIGCHLD directly to that foreign thread.

The embedded entrypoint assembles the Eio 1.2 backend resources and scheduler
without its subprocess manager or SIGCHLD setup. It uses the pinned
`Eio_posix__` implementation modules; changing the Eio version requires reviewing
this integration and rerunning the Worker and native-host tests. This is a
single embedded backend, with no command-line backend fallback.

SIGPIPE is blocked on the dedicated Worker thread before the scheduler starts.
Worker helper threads inherit the mask, so closed writes report errors without
changing the host's SIGPIPE disposition. The mask remains for the owned thread's
lifetime, including shutdown; unmasking a pending SIGPIPE before thread exit
could terminate the host.

Relevant upstream source:
[Eio POSIX entrypoint](https://github.com/ocaml-multicore/eio/blob/v1.2/lib_eio_posix/eio_posix.ml)
and [OCaml 5.1 signal recording](https://github.com/ocaml/ocaml/blob/5.1/runtime/signals.c).

## Validation

`native/test/worker_signal_probe.py` starts the real Network application through
the public native ABI on a background host thread. It delivers SIGCHLD on the
foreign main thread while the runtime is alive and after close, checking both
the default disposition and a custom host handler. Both scenarios crashed before
the embedded entrypoint replaced the command-line entrypoint.

The Network native window scenario exercises actual Worker-backed TLS HTTP and
WSS. OCaml Worker tests cover environment identity, files/network, cancellation,
bounded mailboxes, ordering, restart and teardown. The batch-fairness test now
queues its full workload behind its existing Hold barrier before releasing the
Worker; otherwise a fast consumer could empty the queue between producer sends,
without ever reaching the full-batch condition the test intended to exercise.

The actual OCaml backend now cross-builds into signed iOS 18 arm64 Release Apps,
including Network and SQLite Worker. Their final executables and signatures
pass validation; Network has no unresolved GMP symbols and SQLite Worker links
the iOS system SQLite library. Physical-device Worker behavior remains
unverified. See [example build evidence](swiftui-example-builds.md).
