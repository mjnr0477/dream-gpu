# DREAM GPU v1.3 host driver

This package adds a portable Python software layer for the v1.2 32-bit
memory-mapped host register interface.

## What it does

- Loads up to 256 32-bit instructions.
- Writes and reads the four 64-word lane-private data banks.
- Soft-resets the engine, starts/stops execution, and polls completion/fault status.
- Reads lane accumulators, program counters, and performance counters.
- Validates register values and memory/index bounds before bus access.

## Transport boundary

`DreamGpuDevice` depends only on a transport implementing:

```python
class DreamGpuTransport:
    def read32(self, address: int) -> int: ...
    def write32(self, address: int, value: int) -> None: ...
```

A real board adapter must implement this contract over the chosen physical
link (for example UART, SPI, PCIe, or a board-specific bridge). No such physical
transport is included yet. The test fake validates the software register
protocol only; it is not hardware validation.

## Example

```python
from dream_gpu_driver import DreamGpuDevice

gpu = DreamGpuDevice(board_transport)
gpu.reset()  # clear prior program, data and lane state\ngpu.load_program([0x90000007, 0x20000001, 0x70000000])
for lane, value in enumerate((10, 20, 30, 40)):
    gpu.write_private_word(lane, 7, value)
gpu.start()
gpu.wait_done(max_polls=10000)
print(gpu.results())
```

Run unit tests from the repository root:

```sh
python -m unittest discover -s verification/software -v
```


## v1.6 INT8 tensor operation

The host driver exposes `run_int8_matmul(a, b, max_polls=10000)`. Both inputs must be 4x4 matrices of signed INT8 values (-128..127); the return value is a 4x4 matrix of signed INT32 values. The hardware register map is documented in `architecture/v1_6_tensor_unit.md`.
