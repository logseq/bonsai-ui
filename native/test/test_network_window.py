"""Exercise the real Network app against deterministic loopback TLS endpoints."""
from pathlib import Path
import base64
import hashlib
import http.server
import os
import plistlib
import socket
import ssl
import struct
import subprocess
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]
CERTIFICATES = ROOT / "examples/network/test/fixtures"


class LoopbackHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_arguments):
        pass

    def do_GET(self):
        if self.path == "/socket":
            self.websocket()
            return
        with self.server.lock:
            self.server.requests += 1
            request = self.server.requests
            self.server.request_marker.write_text(str(request))
        self.close_connection = True
        if request == 2:
            self.send_response(200)
            self.send_header("Content-Length", "4096")
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(b"pending")
            self.wfile.flush()
            # The client may half-close its request stream before reading the
            # response. Keep this body incomplete until the test ends instead
            # of treating request EOF as cancellation of the response.
            self.server.release_pending.wait(45)
            return
        if request == 3:
            self.connection.shutdown(socket.SHUT_RDWR)
            return
        body = b"SwiftUI loopback HTTPS"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def websocket(self):
        key = self.headers["Sec-WebSocket-Key"]
        accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        self.send_response(101)
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept)
        self.end_headers()
        self.wfile.flush()
        self.connection.settimeout(10)
        self.close_connection = True
        while True:
            header = self.rfile.read(2)
            if len(header) != 2:
                return
            opcode = header[0] & 15
            size = header[1] & 127
            if size == 126:
                size = struct.unpack("!H", self.rfile.read(2))[0]
            elif size == 127:
                size = struct.unpack("!Q", self.rfile.read(8))[0]
            if not header[1] & 128 or size > 65536:
                raise ValueError("Invalid client frame")
            mask = self.rfile.read(4)
            payload = self.rfile.read(size)
            payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
            if opcode == 8:
                self.connection.sendall(bytes([0x88, len(payload)]) + payload)
                self.server.disconnected.set()
                return
            if opcode == 9:
                self.connection.sendall(bytes([0x8A, len(payload)]) + payload)
            elif opcode == 1:
                text = payload.decode("utf-8")
                self.server.messages.append(text)
                response = ("Echo: " + text).encode("utf-8")
                self.connection.sendall(bytes([0x81, len(response)]) + response)


class LoopbackServer(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, request_marker):
        self.request_marker = request_marker
        request_marker.write_text("0")
        super().__init__(("127.0.0.1", 0), LoopbackHandler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.set_alpn_protocols(["http/1.1"])
        context.load_cert_chain(CERTIFICATES / "localhost-cert.pem", CERTIFICATES / "localhost-key.pem")
        self.socket = context.wrap_socket(self.socket, server_side=True)
        self.lock = threading.Lock()
        self.requests = 0
        self.messages = []
        self.release_pending = threading.Event()
        self.disconnected = threading.Event()


class NetworkWindowTests(unittest.TestCase):
    def test_network_window(self):
        bundle = ROOT / "_build/validation/NetworkWindowAcceptance.app"
        executable = bundle / "Contents/MacOS/NetworkWindowAcceptance"
        executable.parent.mkdir(parents=True, exist_ok=True)
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.bonsai-swiftui.test.network-window",
            "CFBundleName": "NetworkWindowAcceptance", "CFBundleExecutable": executable.name,
            "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "26.0", "LSUIElement": True,
        }))
        native = ROOT / "_build/default/native/test"
        sources = sorted((ROOT / "swift/BonsaiSwiftUI/Sources").glob("*.swift"))
        build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos26.0",
            "-I", str(ROOT / "native/src"), "-L", str(native), "-lruntime_fixture",
            "-Xlinker", "-rpath", "-Xlinker", str(native), *map(str, sources),
            str(ROOT / "swift/BonsaiSwiftUI/Tests/AccessibilitySupport.swift"),
            str(ROOT / "native/test/network_window.swift"), "-o", str(executable)],
            cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
        marker = bundle.parent / "network-requests.txt"
        server = LoopbackServer(marker)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            environment = dict(os.environ, BONSAI_NATIVE_NETWORK_PORT=str(server.server_port),
                BONSAI_NATIVE_NETWORK_CERTIFICATE=str(CERTIFICATES / "localhost-cert.pem"),
                BONSAI_NATIVE_NETWORK_REQUEST_MARKER=str(marker))
            result = subprocess.run([str(executable)], cwd=ROOT, env=environment,
                                    capture_output=True, text=True, timeout=45)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PASS: actual Network window", result.stdout)
            self.assertEqual(server.requests, 3)
            self.assertEqual(server.messages, ["SwiftUI 本地😀"])
            self.assertTrue(server.disconnected.wait(2), "Missing normal WSS close handshake")
            print(result.stdout)
        finally:
            server.release_pending.set()
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
