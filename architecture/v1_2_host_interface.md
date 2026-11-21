# DREAM GPU v1.2 host interface

## Purpose

v1.2 adds a simple memory-mapped host interface around the four-lane v1.1 engine. It is a hardware/software integration prototype: a host can load instructions, preload/read lane-private data, start execution, and read status, counters, PCs, and lane accumulators.

## Host bus

A transaction is accepted on a rising edge when `host_valid` is high. `host_ready` follows `host_valid`; the bus is intentionally simple and has no wait-state or burst protocol.

| Address | Name | Access | Meaning |
|---|---|---|---|
| 0x00 | CONTROL | R/W | bit 0 starts/stops execution; writing bit 1 pulses a self-clearing engine soft reset |
| 0x04 | STATUS | R | bit 7 fault, bit 6 done, bits 5:2 lane halted mask |
| 0x08 | FAULT | R | selected fault code |
| 0x0C | CYCLES | R | maximum lane cycle count |
| 0x10 | INSTRUCTIONS | R | sum of lane instruction counts |
| 0x14 | BRANCHES | R | sum of lane branch counts |
| 0x20 | IMEM_ADDR | R/W | shared instruction-memory word address |
| 0x24 | IMEM_DATA | R/W | instruction data staging register |
| 0x28 | IMEM_COMMIT | W | write staged instruction to IMEM address |
| 0x30 | DMEM_ADDR | R/W | lane in bits 7:6, private word offset in bits 5:0 |
| 0x34 | DMEM_DATA | R/W | private-memory data staging register |
| 0x38 | DMEM_COMMIT | W | write staged word to selected private bank |
| 0x3C | DMEM_READ | R | selected private-memory word |
| 0x40–0x4C | ACCUM[0:3] | R | lane accumulators |
| 0x50–0x5C | PC[0:3] | R | lane program counters |

Instruction memory has 256 words. Each of the four lanes has a 64-word private data bank. Host writes to a private bank take priority over a lane store to the same bank on the same edge; other banks can still accept their lane stores.

## Programming sequence

1. Write instruction address to 0x20.
2. Write instruction to 0x24.
3. Write 1 to 0x28 to commit it.
4. To preload data, write encoded lane/offset to 0x30, data to 0x34, then 1 to 0x38.
5. Write 1 to 0x00 to start execution.
6. Poll 0x04 until done or fault, then read accumulators/counters.

The external reset pin resets the processor and host staging registers. CONTROL bit 1 provides a one-cycle engine soft reset; it clears instruction memory, private memories, lane state, and counters while preserving host staging registers. The bus currently has no interrupt, DMA, burst support, privilege isolation, or formal standard such as AXI4-Lite.

## Verification

`verification/v1_2/tb_dream_gpu_v12_host.v` verifies host instruction loading, private-memory writes and reads, execution start, four lane results, status, and counters. GitHub Actions runs Icarus simulation and Yosys synthesis/structural checks.

## Limits

This is a synthesizable RTL host-bus prototype, not a complete production driver or deployed accelerator. It still needs FPGA constraints, timing closure, board-level I/O validation, a host driver, memory bandwidth analysis, and application-level benchmarking before it can safely serve as DREAM AI's compute backend.
