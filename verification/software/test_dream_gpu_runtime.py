import json
import sys
import threading
import unittest
from http.client import HTTPConnection
from pathlib import Path
from http.server import ThreadingHTTPServer

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "software" / "host"))

from dream_gpu_driver import DreamGpuDevice
from dream_gpu_runtime import make_handler


class RuntimeFakeTransport:
    def __init__(self):
        self.regs = {0x04: 0x7C, 0x40: 11, 0x44: 21, 0x48: 31, 0x4C: 41,
                     0x50: 3, 0x54: 3, 0x58: 3, 0x5C: 3, 0x0C: 3,
                     0x10: 12, 0x14: 0, 0x08: 0}
        self.writes = []

    def read32(self, address):
        return self.regs.get(address, 0)

    def write32(self, address, value):
        self.writes.append((address, value))
        self.regs[address] = value
        if address == 0x00 and value == 1:
            self.regs[0x04] = 0x7C
        if address == 0x38:
            self.regs[0x3C] = self.regs.get(0x34, 0)


class RuntimeApiTests(unittest.TestCase):
    def setUp(self):
        self.transport = RuntimeFakeTransport()
        self.device = DreamGpuDevice(self.transport)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.device, "t" * 32))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.connection = HTTPConnection("127.0.0.1", self.server.server_port, timeout=2)

    def tearDown(self):
        self.connection.close()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def request(self, method, path, body=None, token="t" * 32):
        headers = {"Authorization": f"Bearer {token}"}
        data = None
        if body is not None:
            data = json.dumps(body)
            headers["Content-Type"] = "application/json"
        self.connection.request(method, path, body=data, headers=headers)
        response = self.connection.getresponse()
        raw = response.read()
        return response.status, json.loads(raw) if raw else None

    def test_health_endpoint(self):
        status, payload = self.request("GET", "/health")
        self.assertEqual(status, 200)
        self.assertTrue(payload["device_responding"])
        self.assertEqual(payload["capabilities"]["lanes"], 4)
        self.assertFalse(payload["capabilities"]["physical_fpga_verified"])

    def test_execute_program(self):
        status, payload = self.request("POST", "/v1/execute", {
            "instructions": [0x90000007, 0x20000001, 0x70000000],
            "lane_memory": [[10], [20], [30], [40]],
            "max_polls": 100
        })
        self.assertEqual(status, 200)
        self.assertEqual(payload["accumulators"], [11, 21, 31, 41])
        self.assertIn((0x20, 0), self.transport.writes)
        self.assertIn((0x00, 1), self.transport.writes)

    def test_authentication_required(self):
        status, payload = self.request("GET", "/health", token="wrong")
        self.assertEqual(status, 401)
        self.assertEqual(payload["error"], "unauthorized")

    def test_rejects_invalid_program_and_lane_memory(self):
        status, _ = self.request("POST", "/v1/execute", {"instructions": []})
        self.assertEqual(status, 400)
        status, _ = self.request("POST", "/v1/execute", {
            "instructions": [0x70000000], "lane_memory": [[], []]
        })
        self.assertEqual(status, 400)
        status, _ = self.request("POST", "/v1/execute", {
            "instructions": [True]
        })
        self.assertEqual(status, 400)

    def test_unknown_endpoint(self):
        status, payload = self.request("GET", "/")
        self.assertEqual(status, 404)
        self.assertEqual(payload["error"], "not_found")


if __name__ == "__main__":
    unittest.main()
