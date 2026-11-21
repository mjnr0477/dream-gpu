# DREAM GPU v1.0 instruction set

All instructions are 32 bits. The opcode is bits [31:28].

| Opcode | Mnemonic | Operation |
|---|---|---|
| 0x0 | NOP | Advance selected lane PC |
| 0x1 | MOVI | Load signed 16-bit immediate into accumulator |
| 0x2 | ADDI | Add signed 16-bit immediate |
| 0x3 | SUBI | Subtract signed 16-bit immediate |
| 0x4 | XORI | XOR accumulator with zero-extended 16-bit immediate |
| 0x5 | BRZ | Branch relative if accumulator is zero |
| 0x6 | JMP | Jump to absolute 9-bit instruction address |
| 0x7 | HALT | Halt selected lane |
| 0x8 | LID | Load selected lane ID |
| 0x9 | LD | Load 32-bit value from selected lane private memory |
| 0xA | ST | Store selected lane accumulator to private memory |
| 0xB | MACI | Signed multiply-accumulate from private memory and immediate |

## MACI encoding

- Bits [31:28]: opcode 0xB
- Bits [21:6]: signed 16-bit immediate multiplier
- Bits [5:0]: 6-bit offset within selected lane private memory bank
- Bits [27:22]: reserved; write zero

Operation: accumulator[lane] = accumulator[lane] + signed(memory[lane][offset][15:0]) * signed(immediate).

The selected lane private memory word is interpreted using its low 16 bits as a signed two's-complement value. The product and accumulator are 32-bit; arithmetic wraps modulo 2^32.

Example: 32'hB00000C4 means MACI with immediate +3 and private offset 4.

Example: 32'hB03FFF44 means MACI with immediate -3 and private offset 4.

## Execution model and limits

The engine selects one active lane per clock step using round-robin scheduling. Four lanes are logically independent, but the current RTL does not issue four instructions simultaneously. MACI describes RTL functionality; it does not establish physical GPU performance. Synthesis, timing closure, FPGA mapping, and host software integration are separate milestones.
