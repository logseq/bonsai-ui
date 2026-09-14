"""Compile and execute Swift declarations emitted by the OCaml generator."""

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "_build/default/protocol/generator/generate.exe"
SWIFT_TARGET = "swift/BonsaiSwiftUI/Sources/GeneratedProtocol.swift"


class SwiftGeneratorTests(unittest.TestCase):
    def test_generated_swift_round_trips_ids_and_escapes_keywords(self):
        schema = """((protocol (major 4) (minor 0) (header_bytes 48)
          (max_frame_bytes 65536) (max_string_bytes 1024)
          (max_application_payload_bytes 4096) (max_operations 100) (max_nodes 100))
          (frame_kinds ((full_snapshot 2)))
          (operations ((set_children 5)))
          (node_kinds ((text 2) (switch 7)))
          (event_tags ((press 1)))
          (host_requests ((open_url 2)))
          (runtime_errors ((invalid_prop 5))))"""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for path in ["ocaml/protocol", "protocol/generated", str(Path(SWIFT_TARGET).parent)]:
                (root / path).mkdir(parents=True)
            (root / "protocol/schema.sexp").write_text(schema)
            subprocess.run([str(GENERATOR)], cwd=root, check=True)
            generated = root / SWIFT_TARGET
            self.assertTrue(generated.exists(), "Generator must emit Swift protocol declarations")
            self.assertFalse(list(root.rglob("*.dart")), "Generator must not emit Dart")
            (root / "main.swift").write_text("""
                precondition(ProtocolVersion.protocolMajor == 4)
                precondition(ProtocolVersion.protocolMinor == 0)
                precondition(ProtocolLimits.maxApplicationPayloadBytes == 4096)
                precondition(NodeKindId.text == 2)
                precondition(NodeKindId.switch == 7)
                precondition(NodeKindId.debugName(7) == "switch")
                precondition(NodeKindId.debugName(65535) == nil)
                precondition(OperationId.setChildren == 5)
                precondition(FrameKindId.fullSnapshot == 2)
                precondition(EventTagId.press == 1)
                precondition(HostRequestId.openUrl == 2)
                precondition(RuntimeErrorId.invalidProp == 5)
                print("Generated Swift protocol round trip passed")
            """)
            executable = root / "protocol-check"
            subprocess.run(["xcrun", "swiftc", str(generated), str(root / "main.swift"),
                            "-o", str(executable)], check=True)
            subprocess.run([str(executable)], check=True)
            subprocess.run([str(GENERATOR), "--check"], cwd=root, check=True)
            generated.write_text(generated.read_text() + "// stale\n")
            stale = subprocess.run([str(GENERATOR), "--check"], cwd=root, capture_output=True)
            self.assertNotEqual(stale.returncode, 0)
            self.assertIn(b"GeneratedProtocol.swift", stale.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
