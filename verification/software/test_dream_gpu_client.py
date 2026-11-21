import sys
import threading
import unittest
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "software" / "host"))

from dream_gpu_client import DreamGpuClient, DreamGpuClientError
from dream_gpu_driver import DreamGpuDevice
from dream_gpu_runtime import make_handler


class ClientFakeTransport:
    def __init__(self):
        self.regs = {0x04: 0x7C, 0x0C: 3, 0x10: 12, 0x14: 0}
        self.writes = []

    def read32(self, address):
        return self.regs.get(address, 0)

    def write32(self, address, value):
        self.writes.append((address, value))
        if address == 0x80 and value == 1:
            self.regs[0x84] = 1
        if 0xB0 <= address <= 0xEC and address % 4 == 0:
            pass
        if address == 0x00 and value == 1:
            self.regs[0x04] = 0x7C


class ClientTests(unittest.TestCase):
    def setUp(self):
        self.transport = ClientFakeTransport()
        for index, value in enumerate([1, 4, 3, 4, 5, 16, 7, 8, 9, 28, 11, 12, 13, 40, 15, 16]):
            self.transport.regs[0xB0 + index * 4] = value
        self.device = DreamGpuDevice(self.transport)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.device, "s" * 32))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def test_health_and_int8_matmul(self):
        client = DreamGpuClient(self.base_url, token="s" * 32)
        self.assertTrue(client.health()["device_responding"])
        a = [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12], [13, 14, 15, 16]]
        b = [[1, 2, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
        self.assertEqual(client.matmul_int8(a, b), [
            [1, 4, 3, 4], [5, 16, 7, 8], [9, 28, 11, 12], [13, 40, 15, 16]
        ])

    def test_bad_token_and_invalid_url(self):
        with self.assertRaises(DreamGpuClientError):
            DreamGpuClient(self.base_url, token="wrong").health()
        with self.assertRaises(ValueError):
            DreamGpuClient("file:///etc/passwd")


if __name__ == "__main__":
    unittest.main()
