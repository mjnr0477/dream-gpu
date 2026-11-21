# DREAM GPU v0.3 — Memory subsystem

## Architecture
- Four independent memory banks.
- One bank for each SIMD lane.
- 256 addressable words per bank.
- 16-bit data words.
- Independent 8-bit address per lane.
- Four simultaneous lane writes per clock edge.
- Asynchronous read interface.
- Synchronous write interface.

## Address and data packing
Lane 0: lowest 8 address bits and lowest 16 data bits.
Lane 1: next 8 address bits and next 16 data bits.
Lane 2: next 8 address bits and next 16 data bits.
Lane 3: highest 8 address bits and highest 16 data bits.

## Verification boundary
This version verifies the memory subsystem independently.
It does not yet claim integration with processor load/store instructions.
The next stage will connect the memory interface to the processor.
