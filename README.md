# DREAM GPU

An experimental four-lane GPU-style processor implemented in Verilog RTL.

## Project status

- v0.6: Basic four-lane execution — verified.
- v0.7: Independent lane execution — verified.
- v0.8: Lane-private memory — verified.
- v0.9: Reliability and fault protection — verified.
- v1.0: Candidate with signed MACI multiply-accumulate instruction; regression and synthesis checks run in GitHub Actions.
- v1.1: Four independent lane execution units with simultaneous instruction issue; parallel execution and private-memory MACI tests are in GitHub Actions.

DREAM GPU is currently a simulated RTL design, not a physical GPU, FPGA bitstream, or fabricated ASIC.

## Structure

- rtl/ — processor RTL
- rtl/v1_0/ — v1.0 candidate
- rtl/v1_1/ — four-lane parallel execution prototype
- verification/ — testbenches
- verification/v1_0/ — v1.0 regression tests
- releases/ — versioned archives and SHA-256 checksums

## Requirements

Install Icarus Verilog:

    pkg update
    pkg install iverilog git -y

## Run v1.0 regression tests

From the repository root:

    mkdir -p simulation/v1_0

    iverilog -g2012 -o simulation/v1_0/basic.vvp rtl/v1_0/dream_gpu_core_v10.v rtl/v1_0/dream_gpu_engine_v10.v verification/v1_0/tb_dream_gpu_v10_basic.v
    vvp simulation/v1_0/basic.vvp

    iverilog -g2012 -o simulation/v1_0/divergent.vvp rtl/v1_0/dream_gpu_core_v10.v rtl/v1_0/dream_gpu_engine_v10.v verification/v1_0/tb_dream_gpu_v10_divergent.v
    vvp simulation/v1_0/divergent.vvp

    iverilog -g2012 -o simulation/v1_0/memory.vvp rtl/v1_0/dream_gpu_core_v10.v rtl/v1_0/dream_gpu_engine_v10.v verification/v1_0/tb_dream_gpu_v10_memory.v
    vvp simulation/v1_0/memory.vvp

    iverilog -g2012 -o simulation/v1_0/reliability.vvp rtl/v1_0/dream_gpu_core_v10.v rtl/v1_0/dream_gpu_engine_v10.v verification/v1_0/tb_dream_gpu_v10_reliability.v
    vvp simulation/v1_0/reliability.vvp

    iverilog -g2012 -o simulation/v1_0/maci.vvp rtl/v1_0/dream_gpu_core_v10.v rtl/v1_0/dream_gpu_engine_v10.v verification/v1_0/tb_dream_gpu_v10_maci.v
    vvp simulation/v1_0/maci.vvp

Check for the corresponding TESTS PASS messages and no FAIL messages. The MACI encoding is documented in architecture/v1_0_instruction_set.md. GitHub Actions also runs a Yosys synthesis and structural check.

## Verify release archives

    sha256sum -c releases/dream-gpu-v0.9-verified.sha256
    sha256sum -c releases/dream-gpu-v1.0-candidate.sha256

Keep the verified v0.9 archive unchanged.

## Scope

This project does not claim commercial GPU compatibility or physical GPU performance. v1.0 remains a candidate until independently tested and reviewed.

## License

No license has been declared. Public availability does not automatically grant permission to reuse the code.

## Run v1.1 four-lane parallel test

    iverilog -g2012 -s tb_dream_gpu_v11_parallel -o /tmp/dream_gpu_v11.vvp rtl/v1_1/dream_gpu_lane_v11.v rtl/v1_1/dream_gpu_engine_v11.v verification/v1_1/tb_dream_gpu_v11_parallel.v
    vvp /tmp/dream_gpu_v11.vvp

The v1.1 test checks that all four lane PCs advance on the same clock edge, complete 12 lane-instructions in 3 clocks, and use separate private-memory banks for MACI. See architecture/v1_1_parallel_architecture.md.

