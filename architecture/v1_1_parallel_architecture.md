# DREAM GPU v1.1 parallel execution prototype

## Architecture

v1.1 adds four independent lane execution units. Each lane has its own:
- program counter and accumulator;
- halt and fault state;
- cycle, instruction, and branch counters;
- 64-word private data-memory bank.

The instruction memory is shared and has four asynchronous read ports in this RTL model. All four lane units sample and execute their own current instruction on the same rising clock edge when `run_enable` is asserted. A lane that halts or faults stops independently; the other lanes continue.

This is an MIMD-style four-lane prototype (independent PCs and instruction streams), not a conventional lockstep SIMD core. It is intended to establish real concurrent lane issue in simulation while retaining independent branch paths.

## Supported instructions

The v1.1 lane preserves the v1.0 instruction encodings:
- NOP, MOVI, ADDI, SUBI, XORI
- BRZ, JMP, HALT, LID
- LD, ST
- MACI (signed 16-bit private-memory operand × signed 16-bit immediate, accumulated into 32 bits)

## Verification target

`verification/v1_1/tb_dream_gpu_v11_parallel.v` checks:
1. All four lane PCs advance on the same clock edge.
2. Lane IDs are produced concurrently.
3. Four lane programs complete in 3 clock cycles (12 total lane instructions).
4. Each lane writes to and reads from its own private memory bank through MACI.
5. The parallel MACI program completes in 6 clock cycles (24 total lane instructions).

The test is run in GitHub Actions with Icarus Verilog. Yosys performs hierarchy, structural, and synthesis checks.

## Honest limits

This is RTL simulation and generic synthesis only. It is not proof of FPGA timing, silicon implementation, power efficiency, or speedup on real hardware. The four independent memory read ports and lane datapaths have hardware area costs. An FPGA target, constraints, place-and-route, and board-level testing are still required.
