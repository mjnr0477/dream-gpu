import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "software" / "host"))

from dream_gpu_uart import DreamGpuUartTransport


class FakeSerial:
    def __init__(self, response):
        self.response = bytearray(response)
        self.writes = []
        self.closed = False

    def write(self, data):
        self.writes.append(data)
        return len(data)

    def flush(self):
        pass

    def read(self, size):
        result = self.response[:size]
        del self.response[:size]
        return bytes(result)

    def close(self):
        self.closed = True


class DreamGpuUartTransportTests(unittest.TestCase):
    def test_read_packet_and_little_endian_response(self):
        serial = FakeSerial(b"\x00\x78\x56\x34\x12")
        transport = DreamGpuUartTransport(serial)
        self.assertEqual(transport.read32(0x3C), 0x12345678)
        self.assertEqual(serial.writes, [bytes((0xD5, 0xA5, 0x01, 0x3C))])

    def test_write_packet_and_little_endian_payload(self):
        serial = FakeSerial(b"\x00")
        transport = DreamGpuUartTransport(serial)
        transport.write32(0x34, 0x12345678)
        self.assertEqual(serial.writes, [bytes((0xD5, 0xA5, 0x02, 0x34, 0x78, 0x56, 0x34, 0x12))])

    def test_bad_status_and_timeout(self):
        with self.assertRaises(IOError):
            DreamGpuUartTransport(FakeSerial(b"\x01")).read32(0x00)
        with self.assertRaises(TimeoutError):
            DreamGpuUartTransport(FakeSerial(b"")).read32(0x00)

    def test_bounds(self):
        transport = DreamGpuUartTransport(FakeSerial(b"\x00"))
        with self.assertRaises(ValueError):
            transport.read32(0x02)
        with self.assertRaises(ValueError):
            transport.write32(0x00, -1)

    def test_close(self):
        serial = FakeSerial(b"")
        DreamGpuUartTransport(serial).close()
        self.assertTrue(serial.closed)


if __name__ == "__main__":
    unittest.main()
