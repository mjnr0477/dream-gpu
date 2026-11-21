`timescale 1ns/1ps

// Board-neutral FPGA top-level. Board-specific pin and clock constraints are
// intentionally supplied separately; CLK_HZ must match the actual board clock.
module dream_gpu_fpga_top_v15 #(
    parameter integer CLK_HZ = 50000000,
    parameter integer UART_BAUD = 115200,
    parameter integer WATCHDOG_LIMIT = 100000,
    parameter integer CLKS_PER_BIT = (CLK_HZ + UART_BAUD/2) / UART_BAUD
)(
    input wire clk,
    input wire reset_n,
    input wire uart_rx,
    output wire uart_tx,
    output wire busy,
    output wire done,
    output wire safety_fault,
    output wire [3:0] halted_mask
);
    reg [1:0] reset_sync;
    wire reset = ~reset_sync[1];

    // Asynchronous assertion, synchronous deassertion for the local clock.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            reset_sync <= 2'b00;
        else
            reset_sync <= {reset_sync[0], 1'b1};
    end

    dream_gpu_uart_host_v14 #(
        .CLKS_PER_BIT(CLKS_PER_BIT),
        .WATCHDOG_LIMIT(WATCHDOG_LIMIT)
    ) runtime (
        .clk(clk),
        .reset(reset),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .busy(busy),
        .done(done),
        .safety_fault(safety_fault),
        .halted_mask(halted_mask)
    );
endmodule
