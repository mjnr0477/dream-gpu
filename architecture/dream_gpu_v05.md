# DREAM GPU v0.5 — Programmable execution engine

## Architecture
- 256 x 32-bit instruction memory.
- 8-bit program counter.
- Automatic fetch, issue, wait and halt control.
- Reuses the verified v0.4 compute and data-memory core.
- Host instruction-memory loading interface.
- Host register initialization interface.
- Register debug interface.

## Instruction encoding
[31:28] opcode
[27:25] destination register
[24:22] source register A
[21:19] source register B
[18:16] reserved
[15:0] immediate

## Instruction set
0x0 NOP
0x1 ADD
0x2 SUB
0x3 MUL
0x4 MAC
0x5 MOVI
0x6 LOAD
0x7 STORE
0x8 JUMP — absolute 8-bit instruction address
0x9 BEQZ — branch if lane-zero source register is zero
0xF HALT

## Execution
- Fetch reads the current instruction.
- Normal instructions are issued to the v0.4 core.
- The sequencer waits for the core's completion signal.
- Branch instructions update the program counter.
- HALT stops execution and raises program_done.

## Verification scope
The test program checks arithmetic, memory operations,
taken and non-taken branches, SIMD execution and HALT.

This remains a functional RTL simulation, not physical silicon.
