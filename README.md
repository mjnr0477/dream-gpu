# DREAM GPU

An experimental four-lane integer processor and host-integration project implemented in Verilog RTL.

## Verified development stages

- **v0.6** — basic four-lane execution.
- **v0.7** — independent lane control flow and branching.
- **v0.8** — lane-private data memory.
- **v0.9** — watchdog, invalid-state protection, and recovery; verified archive preserved.
- **v1.0** — signed multiply-accumulate instruction candidate.
- **v1.1** — four independent lane execution units; each lane can execute its own instruction concurrently.
- **v1.2** — memory-mapped host interface for instruction/data loading, start/stop, status, counters, PCs and accumulators.
- **v1.3** — portable Python host driver with a transport abstraction.
- **v1.4** — UART serial bridge and Python UART transport; end-to-end RTL serial simulation passes.
- **v1.5** — board-neutral FPGA top-level with reset synchronizer, plus local HTTP runtime gateway with input validation, optional bearer-token authentication, serialized device access, bounded execution polling, and API tests; host soft reset enables clean repeated jobs.
- **v1.6** — 4x4 signed INT8 matrix-multiply unit, host registers, Python driver, runtime API endpoint, and signed arithmetic testbench.

GitHub Actions runs inherited processor regressions, host-driver/API tests, UART integration simulation, INT8 tensor tests, and Yosys synthesis/structural checks. See the Actions tab for the current branch's exact run status.

## Important status and limitations

DREAM GPU is currently an RTL design validated in simulation and generic Yosys synthesis/structural checks. **It is not yet a physical GPU, FPGA bitstream, fabricated chip, or deployed AI inference accelerator.**

The runtime gateway is a processor execution API, not an LLM inference API. The current design has four integer lanes, integer accumulators, shared instruction memory, and lane-private scratch memory. The v1.6 tensor block is only a small 4x4 signed INT8 matrix-multiply primitive. It does not yet implement floating-point arithmetic, larger tiled matrix operations, quantization scaling/zero-points, convolution, activation functions, transformer operators, external DRAM, DMA, cache coherence, or a complete LLM runtime. DREAM AI must not route model inference to this device until suitable compute capabilities and physical board operation are demonstrated.

Physical deployment still requires a selected FPGA board, board-specific top-level and clock/reset integration, pin and electrical constraints, synthesis/place-and-route, timing closure, programming, and physical UART/functional tests. No board has been assumed or claimed.

## Repository layout

- `rtl/` — processor RTL
- `rtl/v1_0/` through `rtl/v1_6/` — versioned hardware stages
- `software/host/` — Python driver, UART transport, and local HTTP runtime
- `verification/` — RTL testbenches and Python tests
- `architecture/` — ISA, bus, and integration documentation
- `releases/` — versioned archives and SHA-256 checksums

## Requirements

- Python 3.10 or newer
- Icarus Verilog for RTL simulation
- Yosys for generic synthesis/structural checks
- `pyserial` only on the host computer physically connected to a UART FPGA board

## Python tests

From the repository root:

```sh
python -m unittest discover -s verification/software -v
```

The Python tests use fake transports and local HTTP requests. They do not require an FPGA board.

## RTL tests

See `.github/workflows/rtl-regression.yml` for the canonical regression commands. For example, the v1.4 UART integration test can be run with:

```sh
iverilog -g2012 -s tb_dream_gpu_v14_uart -o /tmp/dream_gpu_v14.vvp \
  rtl/v1_1/dream_gpu_lane_v11.v \
  rtl/v1_2/dream_gpu_engine_v12.v \
  rtl/v1_2/dream_gpu_host_v12.v \
  rtl/v1_4/dream_gpu_uart_host_v14.v \
  verification/v1_4/tb_dream_gpu_v14_uart.v
vvp /tmp/dream_gpu_v14.vvp
```

## Host software

- `software/host/dream_gpu_driver.py` — transport-independent register-level device API.
- `software/host/dream_gpu_uart.py` — UART transport for a serial device; requires `pyserial`.
- `software/host/dream_gpu_runtime.py` — loopback-first HTTP runtime API; see `architecture/v1_5_runtime_api.md`.

Start the runtime after connecting a compatible FPGA board:

```sh
python -m pip install pyserial
python software/host/dream_gpu_runtime.py --serial-port /dev/ttyUSB0 --baudrate 115200
```

The API listens on `127.0.0.1:8765` by default. A non-loopback bind requires a bearer token of at least 24 characters. Use a TLS reverse proxy and firewall for any remote deployment; the built-in server does not provide TLS.

- `GET /health` — checks register-level device responsiveness and reports capabilities.
- `POST /v1/execute` — loads raw 32-bit instruction words, optionally preloads four lane-private memory banks, starts execution, and returns lane results.
- `POST /v1/matmul/int8` — computes a 4x4 signed INT8 matrix product and returns signed INT32 outputs.

## Release archives

Verify preserved release checksums from the repository root:

```sh
sha256sum -c releases/dream-gpu-v0.9-verified.sha256
sha256sum -c releases/dream-gpu-v1.0-candidate.sha256
```

The v0.9 verified archive must remain unchanged.

## License

No license has been declared. Public availability does not automatically grant permission to reuse the code.

- **v1.6** — 4x4 signed INT8 matrix multiply unit, memory-mapped host registers, signed arithmetic verification, and a Python driver/API operation.
