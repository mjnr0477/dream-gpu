# DREAM GPU v1.5 board-neutral FPGA top

The module `dream_gpu_fpga_top_v15` is the board-facing top-level wrapper.
It integrates the UART host bridge and provides asynchronous reset assertion
with synchronous deassertion.

## Clock and UART parameters

- `CLK_HZ`: actual board clock frequency in hertz.
- `UART_BAUD`: serial baud rate (default 115200).
- `CLKS_PER_BIT`: rounded integer divider, derived from the two parameters.
- `WATCHDOG_LIMIT`: lane watchdog limit.

The clock value must be changed to match the board oscillator. The UART
divider is approximate and must be validated against baud tolerance on the
selected board.

## External ports

| Port | Direction | Requirement |
|---|---|---|
| clk | input | Board oscillator, exact frequency required |
| reset_n | input | Active-low reset |
| uart_rx | input | 3.3 V or board-compatible UART receive |
| uart_tx | output | UART transmit |
| busy | output | Accelerator executing |
| done | output | All lanes halted |
| safety_fault | output | Safety fault indicator |
| halted_mask[3:0] | output | Per-lane halted state |

No board pin numbers or I/O standards are declared because no specific FPGA
board has been selected. Do not connect signals until the selected board's
voltage standards and pinout are confirmed. A USB-to-UART adapter must use
compatible logic voltage and common ground; never connect RS-232 voltage
levels directly to FPGA pins.

## Acceptance steps for a physical board

1. Set `CLK_HZ` to the oscillator value on the selected board.
2. Add the board's actual pin constraints and I/O standards.
3. Run the vendor/open-source synthesis and place-and-route flow.
4. Confirm timing closure and resource utilization.
5. Program the board and verify UART loopback/host register reads.
6. Run the full four-lane memory and execution test over physical UART.

This top-level wrapper and its simulation test are not evidence of physical
FPGA operation.
