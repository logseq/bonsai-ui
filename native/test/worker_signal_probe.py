"""Probe embedded Worker signal ownership from a foreign host thread."""
import ctypes
import os
import signal
import sys
import threading
from test_runtime import NativeRuntimeTests, Output, bootstrap

received = []
if sys.argv[1] == "custom":
    signal.signal(signal.SIGCHLD, lambda number, _frame: received.append(number))
else:
    signal.signal(signal.SIGCHLD, signal.SIG_DFL)

ready = threading.Event()
stop = threading.Event()
failures = []


def worker():
    try:
        harness = NativeRuntimeTests()
        harness.library = ctypes.CDLL(os.environ["BONSAI_NATIVE_TEST_LIBRARY"])
        harness.connect()
        config = bootstrap("network")
        runtime = harness.create(config, len(config))
        assert runtime, "Network runtime did not start"
        try:
            output = Output()
            assert harness.pump(runtime, 1, None, 0, ctypes.byref(output)) == 0
            token, revision = output.presentation_id, output.revision
            assert b"HTTPS: Idle" in harness.consume(runtime, output)
            assert harness.present(runtime, token, revision, 2, ctypes.byref(output)) == 0
            harness.consume(runtime, output)
            ready.set()
            assert stop.wait(10), "Host signal probe did not finish"
        finally:
            harness.destroy(runtime)
    except BaseException as error:
        failures.append(error)
        ready.set()


thread = threading.Thread(target=worker)
thread.start()
assert ready.wait(10), "Worker startup timed out"
assert not failures, failures
libc = ctypes.CDLL(None)
raise_signal = getattr(libc, "raise")
raise_signal.argtypes = [ctypes.c_int]
raise_signal.restype = ctypes.c_int
try:
    for _ in range(3):
        assert raise_signal(signal.SIGCHLD) == 0
finally:
    stop.set()
    thread.join(timeout=10)
assert not thread.is_alive() and not failures, failures
assert raise_signal(signal.SIGCHLD) == 0
if sys.argv[1] == "custom":
    assert received == [signal.SIGCHLD] * 4, received
print("PASS: embedded Worker preserves host SIGCHLD during and after runtime lifetime")
