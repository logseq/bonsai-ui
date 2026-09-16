"""Exercise the public C ABI against an embedded, real Bonsai counter."""

import ctypes
import os
import struct
import subprocess
import sys
from pathlib import Path
import unittest


class Output(ctypes.Structure):
    _fields_ = [
        ("data", ctypes.c_void_p),
        ("length", ctypes.c_size_t),
        ("presentation_id", ctypes.c_uint64),
        ("revision", ctypes.c_uint64),
        ("status", ctypes.c_int32),
        ("error_code", ctypes.c_int32),
    ]


def bootstrap(entrypoint="counter"):
    name = entrypoint.encode()
    return struct.pack("<4sHHB3xII", b"BSR1", 1, 0, 1, len(name), 0) + name


class NativeRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.library = ctypes.CDLL(os.environ["BONSAI_NATIVE_TEST_LIBRARY"])

    def function(self, name, arguments, result):
        function = getattr(self.library, name, None)
        self.assertIsNotNone(function, f"Missing SwiftUI native export: {name}")
        function.argtypes = arguments
        function.restype = result
        return function

    def test_worker_preserves_foreign_host_signal_handlers(self):
        for disposition in ("default", "custom"):
            with self.subTest(disposition=disposition):
                result = subprocess.run(
                    [sys.executable, str(Path(__file__).with_name("worker_signal_probe.py")), disposition],
                    capture_output=True, text=True, timeout=25)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("PASS: embedded Worker preserves host SIGCHLD", result.stdout)

    def test_version_and_obsolete_exports(self):
        major = self.function("bs_abi_version_major", [], ctypes.c_uint16)
        minor = self.function("bs_abi_version_minor", [], ctypes.c_uint16)
        self.assertEqual((major(), minor()), (4, 0))
        for name in ("bf_runtime_create", "bf_runtime_pump", "bf_abi_version_major"):
            self.assertIsNone(getattr(self.library, name, None), name)

    def connect(self):
        self.create = self.function("bs_runtime_create", [ctypes.c_char_p, ctypes.c_size_t], ctypes.c_void_p)
        self.destroy = self.function("bs_runtime_destroy", [ctypes.c_void_p], None)
        self.pump = self.function("bs_runtime_pump", [ctypes.c_void_p, ctypes.c_int64, ctypes.c_char_p, ctypes.c_size_t, ctypes.POINTER(Output)], ctypes.c_int32)
        self.present = self.function("bs_runtime_presentation_succeeded", [ctypes.c_void_p, ctypes.c_uint64, ctypes.c_uint64, ctypes.c_int64, ctypes.POINTER(Output)], ctypes.c_int32)
        self.reject = self.function("bs_runtime_presentation_rejected", [ctypes.c_void_p, ctypes.c_uint64, ctypes.c_uint64, ctypes.c_int32, ctypes.POINTER(Output)], ctypes.c_int32)
        self.free = self.function("bs_buffer_free", [ctypes.c_void_p, ctypes.c_void_p], None)
        self.outstanding = self.function("bs_runtime_outstanding_buffers", [ctypes.c_void_p], ctypes.c_size_t)

    def start(self):
        self.connect()
        config = bootstrap()
        runtime = self.create(config, len(config))
        self.assertTrue(runtime, "Real OCaml counter must initialize")
        self.addCleanup(self.destroy, runtime)
        return runtime

    def consume(self, runtime, output):
        data = ctypes.string_at(output.data, output.length) if output.data else b""
        self.free(runtime, output.data)
        self.assertEqual(self.outstanding(runtime), 0)
        return data

    def test_real_counter_initial_frame_and_empty_presentation(self):
        runtime = self.start()
        output = Output()
        self.assertEqual(self.pump(runtime, 1, None, 0, ctypes.byref(output)), 0)
        self.assertGreater(output.presentation_id, 0)
        self.assertGreater(output.revision, 0)
        token, revision = output.presentation_id, output.revision
        frame = self.consume(runtime, output)
        self.assertIn(b"Count: 0", frame)
        self.assertIn(b"Increment", frame)
        self.assertEqual(self.present(runtime, token, revision, 2, ctypes.byref(output)), 0)
        self.consume(runtime, output)
        self.assertEqual(self.pump(runtime, 3, None, 0, ctypes.byref(output)), 0)
        self.assertGreater(output.presentation_id, token)
        self.assertEqual(output.revision, revision)
        self.assertEqual(self.consume(runtime, output), b"")

    def test_terminal_shutdown_retires_pending_token_without_presentation(self):
        runtime = self.start()
        shutdown = self.function("bs_runtime_shutdown_pump", [ctypes.c_void_p,
            ctypes.c_int64, ctypes.c_char_p, ctypes.c_size_t, ctypes.POINTER(Output)], ctypes.c_int32)
        output = Output()
        self.assertEqual(self.pump(runtime, 1, None, 0, ctypes.byref(output)), 0)
        token, revision = output.presentation_id, output.revision
        self.consume(runtime, output)
        self.assertEqual(shutdown(runtime, 2, None, 0, ctypes.byref(output)), 0)
        self.assertEqual((output.presentation_id, output.revision), (0, 0))
        self.assertEqual(self.consume(runtime, output), b"BSSD" + bytes(4))
        self.assertNotEqual(self.present(runtime, token, revision, 3, ctypes.byref(output)), 0)
        self.consume(runtime, output)
        self.assertNotEqual(self.pump(runtime, 4, None, 0, ctypes.byref(output)), 0)
        self.consume(runtime, output)
        self.assertNotEqual(shutdown(runtime, 1, None, 0, ctypes.byref(output)), 0)
        self.consume(runtime, output)
        self.assertNotEqual(shutdown(runtime, 5, b"bad", 3, ctypes.byref(output)), 0)
        self.consume(runtime, output)
        self.assertEqual(shutdown(runtime, 6, None, 0, ctypes.byref(output)), 0)
        self.assertEqual(self.consume(runtime, output), b"BSSD" + bytes(4))

    def test_rejected_frame_recovers_with_full_snapshot(self):
        runtime = self.start()
        output = Output()
        self.assertEqual(self.pump(runtime, 10, None, 0, ctypes.byref(output)), 0)
        token, revision = output.presentation_id, output.revision
        self.consume(runtime, output)
        self.assertEqual(self.reject(runtime, token, revision, 1, ctypes.byref(output)), 0)
        self.consume(runtime, output)
        self.assertEqual(self.pump(runtime, 11, None, 0, ctypes.byref(output)), 0)
        self.assertGreater(output.revision, revision)
        self.assertIn(b"Count: 0", self.consume(runtime, output))

    def test_pump_without_acknowledgment_is_rejected(self):
        runtime = self.start()
        output = Output()
        self.assertEqual(self.pump(runtime, 20, None, 0, ctypes.byref(output)), 0)
        self.consume(runtime, output)
        self.assertNotEqual(self.pump(runtime, 21, None, 0, ctypes.byref(output)), 0)
        self.assertNotEqual(output.error_code, 0)
        self.assertEqual(output.presentation_id, 0)
        self.consume(runtime, output)

    def test_invalid_startup_and_restart(self):
        self.connect()
        for config in (b"", b"counter", b"BFR1" + bootstrap()[4:], bootstrap("missing-entrypoint"), bootstrap()[:-1]):
            self.assertFalse(self.create(config, len(config)))
        for _ in range(3):
            config = bootstrap()
            runtime = self.create(config, len(config))
            self.assertTrue(runtime)
            output = Output()
            self.assertEqual(self.pump(runtime, 1, None, 0, ctypes.byref(output)), 0)
            self.assertIn(b"Count: 0", self.consume(runtime, output))
            self.destroy(runtime)


if __name__ == "__main__":
    unittest.main(verbosity=2)
