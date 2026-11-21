# DREAM GPU v0.4 — Memory-connected processor

## New instructions
- 0x6 LOAD: regs[lane][rd] = memory[regs[lane][ra][7:0]]
- 0x7 STORE: memory[regs[lane][ra][7:0]] = regs[lane][rb]

## Architecture
- Four SIMD compute lanes.
- Four independent 256 x 16-bit memory banks.
- Independent per-lane addresses and data.
- Synchronous memory writes.
- Combinational memory reads.
- Existing arithmetic instructions retained.
- Existing host register write and debug interfaces retained.

## Verification
The v0.4 integration test checks:
- Four-lane independent STORE.
- Four-lane LOAD.
- Positive and negative signed data.
- Register readback.
- Arithmetic ADD after memory operations.

Memory contents are not reset by processor reset.
This version is a functional RTL simulation, not physical silicon.
