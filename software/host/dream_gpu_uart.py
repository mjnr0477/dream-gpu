"""UART packet transport for DREAM GPU v1.4.

The supplied serial object must provide write(bytes), read(size), and optionally
flush(). Install pyserial only when using a real serial port.
"""
from __future__ import annotations


class DreamGpuUartTransport:
    SYNC = bytes((0xD5, 0xA5))
    READ = 0x01
    WRITE = 0x02

    def __init__(self, serial_port):
        self.serial = serial_port

    @classmethod
    def open(cls, port: str, baudrate: int = 115200, timeout: float = 2.0):
        try:
            import serial
        except ImportError as exc:
            raise RuntimeError("Install pyserial to open a physical UART port") from exc
        return cls(serial.Serial(port=port, baudrate=baudrate, timeout=timeout))

    def _exchange(self, command: int, address: int, value: int | None = None) -> bytes:
        if not isinstance(address, int) or address not in range(0, 256, 4):
            raise ValueError("register address must be aligned and within 0x00..0xFC")
        packet = bytearray(self.SYNC)
        packet.extend((command, address))
        if value is not None:
            if not isinstance(value, int) or not 0 <= value <= 0xFFFFFFFF:
                raise ValueError("register values must be unsigned 32-bit integers")
            packet.extend(value.to_bytes(4, "little"))
        written = self.serial.write(bytes(packet))
        if written is not None and written != len(packet):
            raise IOError("incomplete UART packet write")
        if hasattr(self.serial, "flush"):
            self.serial.flush()
        response = self.serial.read(1)
        if len(response) != 1:
            raise TimeoutError("timed out waiting for DREAM GPU UART status")
        if response[0] != 0:
            raise IOError(f"DREAM GPU UART bridge returned status {response[0]}")
        if command == self.READ:
            data = self.serial.read(4)
            if len(data) != 4:
                raise TimeoutError("timed out waiting for DREAM GPU UART read data")
            return data
        return b""

    def read32(self, address: int) -> int:
        return int.from_bytes(self._exchange(self.READ, address), "little")

    def write32(self, address: int, value: int) -> None:
        self._exchange(self.WRITE, address, value)

    def close(self) -> None:
        self.serial.close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        self.close()
