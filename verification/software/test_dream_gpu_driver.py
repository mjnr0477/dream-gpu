import unittest

from dream_gpu_driver import DreamGpuDevice


class FakeTransport:
    def __init__(self):
        self.registers = {}
        self.writes = []

    def read32(self, address):
        return self.registers.get(address, 0)

    def write32(self, address, value):
        self.writes.append((address, value))
        self.registers[address] = value
        if address == DreamGpuDevice.DMEM_COMMIT:
            self.registers[DreamGpuDevice.DMEM_READ] = self.registers.get(DreamGpuDevice.DMEM_DATA, 0)


class DreamGpuDriverTests(unittest.TestCase):
    def setUp(self):
        self.bus = FakeTransport()
        self.gpu = DreamGpuDevice(self.bus)

    def test_program_loading_register_sequence(self):
        count = self.gpu.load_program([0x90000007, 0x20000001, 0x70000000])
        self.assertEqual(count, 3)
        self.assertEqual(self.bus.writes, [
            (0x20, 0), (0x24, 0x90000007), (0x28, 1),
            (0x20, 1), (0x24, 0x20000001), (0x28, 1),
            (0x20, 2), (0x24, 0x70000000), (0x28, 1),
        ])

    def test_private_memory_lane_addressing(self):
        self.gpu.write_private_word(3, 7, 0xAABBCCDD)
        self.assertEqual(self.bus.writes, [
            (0x30, (3 << 6) | 7),
            (0x34, 0xAABBCCDD),
            (0x38, 1),
        ])
        self.assertEqual(self.gpu.read_private_word(3, 7), 0xAABBCCDD)

    def test_status_decode_and_wait(self):
        self.bus.registers[0x04] = 0x7C
        state = self.gpu.wait_done(max_polls=1)
        self.assertTrue(state.done)
        self.assertFalse(state.fault)
        self.assertEqual(state.halted_mask, 0xF)

    def test_fault_is_reported(self):
        self.bus.registers[0x04] = 0x80
        self.bus.registers[0x08] = 4
        with self.assertRaisesRegex(RuntimeError, "fault 4"):
            self.gpu.wait_done(max_polls=1)

    def test_timeout(self):
        with self.assertRaises(TimeoutError):
            self.gpu.wait_done(max_polls=2)

    def test_bounds_are_checked(self):
        with self.assertRaises(ValueError):
            self.gpu.write_private_word(4, 0, 1)
        with self.assertRaises(ValueError):
            self.gpu.write_private_word(0, 64, 1)
        with self.assertRaises(ValueError):
            self.gpu.load_program([0] * 2, start_index=255)
        with self.assertRaises(ValueError):
            self.gpu.write_register(0x00, -1)


if __name__ == "__main__":
    unittest.main()
