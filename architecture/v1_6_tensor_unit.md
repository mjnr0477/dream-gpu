# DREAM GPU v1.6 INT8 tensor unit

## Compute operation

The v1.6 tensor unit uses 16 signed 8x8 multipliers for the active row and computes:

`C[r][c] = sum(k=0..3, signed_int8(A[r][k]) * signed_int8(B[k][c]))`

for 4x4 matrices. Each output is a signed 32-bit integer. All 16 products for one output row are combinationally evaluated, and one row (four results) is committed per clock for four compute clocks. This avoids instantiating 64 multipliers for all 16 outputs at once.

## Host register map

| Address | Name | Access | Meaning |
|---|---|---|---|
| 0x80 | TENSOR_CONTROL | W | bit 0 starts a matrix operation |
| 0x84 | TENSOR_STATUS | R | bit 0 done, bit 1 busy |
| 0x90–0x9C | MATRIX_A_ROW[0:3] | W | Four signed INT8 values packed little-endian in each row |
| 0xA0–0xAC | MATRIX_B_ROW[0:3] | W | Four signed INT8 values packed little-endian in each row |
| 0xB0–0xEC | MATRIX_C[0:15] | R | Signed INT32 output values in row-major order |

A soft reset through base CONTROL address 0x00 bit 1 clears the tensor's input and output registers as well as the main processor's memories/state.

## Software

`DreamGpuDevice.run_int8_matmul(a, b)` packs and loads the matrices, starts the tensor unit, polls status, and returns signed INT32 results. The local runtime API exposes this through `POST /v1/matmul/int8`.

## Verification and limits

The v1.6 testbench checks a nontrivial matrix product, signed negative values, result register addressing, and reset. The design is an initial 4x4 integer tensor primitive. It has no floating point, larger matrix tiling, external memory, DMA, activation functions, quantization scaling/zero-points, convolution, transformer operators, or LLM runtime. It has not been tested on a physical FPGA board.
