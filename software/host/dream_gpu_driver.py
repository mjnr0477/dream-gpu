"""Portable host-side driver for the DREAM GPU v1.2 register bus.

The transport is deliberately abstract: this module does not pretend to provide
UART, SPI, PCIe, USB, or FPGA-board access. A board-specific adapter must
implement read32(address) and write32(address, value).
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Protocol


class DreamGpuTransport(Protocol):
    def read32(self, address: int) -> int: ...
    def write32(self, address: int, value: int) -> None: ...


@dataclass(frozen=True)
class DreamGpuStatus:
    raw: int
    halted_mask: int
    done: bool
    fault: bool


@dataclass(frozen=True)
class DreamGpuResults:
    accumulators: tuple[int, int, int, int]
    program_counters: tuple[int, int, int, int]
    status: DreamGpuStatus
    fault_code: int
    cycles: int
    instructions: int
    branches: int


class DreamGpuDevice:
    CONTROL = 0x00
    STATUS = 0x04
    FAULT = 0x08
    CYCLES = 0x0C
    INSTRUCTIONS = 0x10
    BRANCHES = 0x14
    IMEM_ADDR = 0x20
    IMEM_DATA = 0x24
    IMEM_COMMIT = 0x28
    DMEM_ADDR = 0x30
    DMEM_DATA = 0x34
    DMEM_COMMIT = 0x38
    DMEM_READ = 0x3C
    ACCUMULATORS = (0x40, 0x44, 0x48, 0x4C)
    PROGRAM_COUNTERS = (0x50, 0x54, 0x58, 0x5C)
    TENSOR_CONTROL = 0x80
    TENSOR_STATUS = 0x84
    TENSOR_A_BASE = 0x90
    TENSOR_B_BASE = 0xA0
    TENSOR_C_BASE = 0xB0

    def __init__(self, transport: DreamGpuTransport):
        self.transport = transport

    @staticmethod
    def _u32(value: int) -> int:
        if not isinstance(value, int) or not 0 <= value <= 0xFFFFFFFF:
            raise ValueError("register values must be unsigned 32-bit integers")
        return value

    @staticmethod
    def _lane_offset(lane: int, offset: int) -> int:
        if lane not in range(4):
            raise ValueError("lane must be in range 0..3")
        if offset not in range(64):
            raise ValueError("private-memory offset must be in range 0..63")
        return (lane << 6) | offset

    @staticmethod
    def _instruction_index(index: int) -> int:
        if index not in range(256):
            raise ValueError("instruction index must be in range 0..255")
        return index

    def read_register(self, address: int) -> int:
        if address not in range(0, 256, 4):
            raise ValueError("register address must be 32-bit aligned and within 0x00..0xFC")
        return self._u32(self.transport.read32(address))

    def write_register(self, address: int, value: int) -> None:
        if address not in range(0, 256, 4):
            raise ValueError("register address must be 32-bit aligned and within 0x00..0xFC")
        self.transport.write32(address, self._u32(value))

    def load_program(self, words: Iterable[int], start_index: int = 0) -> int:
        program = tuple(self._u32(word) for word in words)
        if start_index not in range(256) or start_index + len(program) > 256:
            raise ValueError("program must fit in the 256-word instruction memory")
        for index, word in enumerate(program, start_index):
            self.write_register(self.IMEM_ADDR, index)
            self.write_register(self.IMEM_DATA, word)
            self.write_register(self.IMEM_COMMIT, 1)
        return len(program)

    def write_private_word(self, lane: int, offset: int, value: int) -> None:
        address = self._lane_offset(lane, offset)
        self.write_register(self.DMEM_ADDR, address)
        self.write_register(self.DMEM_DATA, self._u32(value))
        self.write_register(self.DMEM_COMMIT, 1)

    def read_private_word(self, lane: int, offset: int) -> int:
        self.write_register(self.DMEM_ADDR, self._lane_offset(lane, offset))
        return self.read_register(self.DMEM_READ)

    def reset(self) -> None:
        """Pulse the host soft-reset bit; clears program and lane memories."""
        self.write_register(self.CONTROL, 2)
        self.write_register(self.CONTROL, 0)

    def start(self) -> None:
        self.write_register(self.CONTROL, 1)

    def stop(self) -> None:
        self.write_register(self.CONTROL, 0)

    def status(self) -> DreamGpuStatus:
        raw = self.read_register(self.STATUS)
        return DreamGpuStatus(
            raw=raw,
            halted_mask=(raw >> 2) & 0xF,
            done=bool(raw & (1 << 6)),
            fault=bool(raw & (1 << 7)),
        )

    def wait_done(self, max_polls: int = 10000) -> DreamGpuStatus:
        if not isinstance(max_polls, int) or max_polls <= 0:
            raise ValueError("max_polls must be a positive integer")
        for _ in range(max_polls):
            state = self.status()
            if state.fault:
                code = self.read_register(self.FAULT)
                raise RuntimeError(f"DREAM GPU reported safety fault {code}")
            if state.done:
                return state
        raise TimeoutError(f"DREAM GPU did not finish within {max_polls} status polls")

    @staticmethod
    def _pack_int8_row(row: Iterable[int]) -> int:
        values = tuple(row)
        if len(values) != 4:
            raise ValueError("each INT8 matrix row must contain exactly four values")
        packed = 0
        for index, value in enumerate(values):
            if isinstance(value, bool) or not isinstance(value, int) or not -128 <= value <= 127:
                raise ValueError("INT8 matrix values must be integers in range -128..127")
            packed |= (value & 0xFF) << (index * 8)
        return packed

    def run_int8_matmul(self, matrix_a, matrix_b, max_polls: int = 10000):
        """Run a 4x4 signed INT8 matrix product and return a 4x4 signed INT32 matrix."""
        if not isinstance(max_polls, int) or isinstance(max_polls, bool) or max_polls <= 0:
            raise ValueError("max_polls must be a positive integer")
        if not isinstance(matrix_a, (list, tuple)) or len(matrix_a) != 4:
            raise ValueError("matrix_a must be a 4x4 matrix")
        if not isinstance(matrix_b, (list, tuple)) or len(matrix_b) != 4:
            raise ValueError("matrix_b must be a 4x4 matrix")
        packed_a = tuple(self._pack_int8_row(row) for row in matrix_a)
        packed_b = tuple(self._pack_int8_row(row) for row in matrix_b)
        for row, value in enumerate(packed_a):
            self.write_register(self.TENSOR_A_BASE + row * 4, value)
        for row, value in enumerate(packed_b):
            self.write_register(self.TENSOR_B_BASE + row * 4, value)
        self.write_register(self.TENSOR_CONTROL, 1)
        for _ in range(max_polls):
            status = self.read_register(self.TENSOR_STATUS)
            if status & 1:
                flat = []
                for index in range(16):
                    value = self.read_register(self.TENSOR_C_BASE + index * 4)
                    flat.append(value - 0x100000000 if value & 0x80000000 else value)
                return tuple(tuple(flat[row * 4 + col] for col in range(4)) for row in range(4))
            if not status & 2:
                raise RuntimeError("INT8 tensor unit stopped without setting done")
        raise TimeoutError(f"INT8 tensor unit did not finish within {max_polls} status polls")

    def results(self) -> DreamGpuResults:
        state = self.status()
        return DreamGpuResults(
            accumulators=tuple(self.read_register(a) for a in self.ACCUMULATORS),
            program_counters=tuple(self.read_register(a) for a in self.PROGRAM_COUNTERS),
            status=state,
            fault_code=self.read_register(self.FAULT),
            cycles=self.read_register(self.CYCLES),
            instructions=self.read_register(self.INSTRUCTIONS),
            branches=self.read_register(self.BRANCHES),
        )
