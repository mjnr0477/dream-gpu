# DREAM GPU v1.5 runtime API

The runtime API is a local HTTP gateway between software clients and a
DREAM GPU host transport. It uses only Python's standard library. The UART
adapter requires `pyserial` on the computer physically connected to the FPGA.

## Start

```sh
python -m pip install pyserial
python software/host/dream_gpu_runtime.py --serial-port /dev/ttyUSB0 --baudrate 115200
```

The service binds to `127.0.0.1:8765` by default. It deliberately does not
listen on a public interface by default. To bind to another interface, provide
a random API token of at least 24 characters using `--token` or
`DREAM_GPU_API_TOKEN`. For a remote deployment, put it behind a TLS-enabled
reverse proxy and firewall; the built-in HTTP server is not TLS.

## Endpoints

- `GET /health` — reads device status and counters and reports implemented
  capabilities. It explicitly reports that physical FPGA validation is false
  until board-level acceptance testing is completed.
- `POST /v1/execute` — loads a raw instruction program, optionally preloads
  up to 64 words for each of four lane-private memories, starts execution,
  soft-resets the engine, loads the program, waits for completion, and returns accumulators, PCs and counters.

Example JSON body:

```json
{
  "instructions": [2415919111, 536870913, 1879048192],
  "lane_memory": [[10], [20], [30], [40]],
  "max_polls": 10000
}
```

The instruction words are raw DREAM GPU ISA values; clients are responsible
for supplying valid programs. Requests are size-bounded, input-validated, and
serialized so two API requests cannot interleave register transactions.

## Important limits

This is a processor execution API, not a language-model inference API. The
current RTL has four integer execution lanes, private scratch memory and
integer accumulators. It does not implement floating point, tensor/matrix
operations, a neural-network instruction set, DRAM, DMA, or an LLM runtime.
DREAM AI must not route model inference to this accelerator until those
capabilities exist and the board has passed physical tests.

The fake-transport tests validate API behavior and register sequencing only.
They do not establish that a real FPGA exists or is connected.


## INT8 tensor endpoint (v1.6)

- `POST /v1/matmul/int8` accepts two 4x4 matrices named `a` and `b`, with signed INT8 values in the range -128..127.
- Returns a 4x4 signed INT32 matrix.
- The v1.6 tensor block uses 16 signed 8x8 multipliers to compute one output row per clock over four clocks. It is a small fixed-point building block, not a complete neural-network accelerator.


The application-facing client is `software/host/dream_gpu_client.py`; it provides `health()`, `matmul_int8()`, and `execute()` methods for a future application adapter. See `architecture/v1_6_application_client.md`.
