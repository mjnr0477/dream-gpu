`timescale 1ns/1ps
module tb_dream_gpu_v15_top;
    reg clk=0;
    reg reset_n=0;
    reg uart_rx=1;
    wire uart_tx,busy,done,safety_fault;
    wire [3:0] halted_mask;

    always #5 clk=~clk;

    dream_gpu_fpga_top_v15 #(
        .CLK_HZ(100000000),
        .UART_BAUD(6250000),
        .WATCHDOG_LIMIT(1000)
    ) dut(
        .clk(clk),.reset_n(reset_n),.uart_rx(uart_rx),.uart_tx(uart_tx),
        .busy(busy),.done(done),.safety_fault(safety_fault),
        .halted_mask(halted_mask)
    );

    initial begin
        repeat(4) @(posedge clk);
        if (uart_tx!==1'b1) $fatal(1,"UART TX must idle high during reset");
        reset_n=1;
        repeat(5) @(posedge clk);
        if (uart_tx!==1'b1) $fatal(1,"UART TX idle level invalid after reset");
        if (busy!==1'b0) $fatal(1,"GPU must remain idle after reset");
        if (safety_fault!==1'b0) $fatal(1,"Unexpected fault after reset");
        $display("PASS: board-neutral top reset synchronizer and UART idle");
        $display("DREAM GPU v1.5 FPGA TOP TEST PASS");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1,"top-level test timeout");
    end
endmodule
