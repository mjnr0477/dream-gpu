# DREAM GPU v0.2

Independent parallel AI processor prototype.

## Processing architecture

- Four SIMD execution lanes.
- Eight 16-bit registers per lane.
- Eight 40-bit accumulators per lane.
- Independent lane register banks.
- Shared instruction stream.
- Instruction decoder.
- Instruction controller.
- Host register-loading interface.
- Debug register access.
- Debug accumulator access.

## Instructions

0000 NOP
0001 ADD
0010 SUB
0011 MUL
0100 MAC
0101 MOVI

## Arithmetic

ADD: 16-bit addition.
SUB: 16-bit subtraction.
MUL: signed 16-bit multiplication, low 16-bit result.
MAC: signed 16-bit multiplication with 40-bit accumulation.
MOVI: load an immediate value.

## Important limitations

This is an initial RTL processor prototype.

It does not yet contain:
- External memory controller.
- DMA.
- Cache hierarchy.
- Operating system driver.
- Compiler.
- Physical GPU silicon.

Simulation does not prove physical performance.
