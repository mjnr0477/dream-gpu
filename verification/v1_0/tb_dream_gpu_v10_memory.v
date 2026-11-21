`timescale 1ns/1ps

module tb_dream_gpu_v10_memory;

    reg clk = 0;
    reg reset = 1;
    reg run_enable = 0;

    reg imem_write = 0;
    reg [7:0] imem_address = 0;
    reg [31:0] imem_data = 0;

    wire [3:0] lane_mask;
    wire [35:0] pc_bus;
    wire [127:0] accum_bus;

    wire safety_fault;
    wire done;

    wire [31:0] cycle_count;
    wire [31:0] instruction_count;
    wire [31:0] branch_count;
    wire [1:0] selected_lane;

    integer i;

    always #5 clk = ~clk;

    dream_gpu_engine_v10 dut (
        .clk(clk),
        .reset(reset),
        .run_enable(run_enable),

        .imem_write(imem_write),
        .imem_address(imem_address),
        .imem_data(imem_data),

        .lane_mask(lane_mask),
        .pc_bus(pc_bus),
        .accum_bus(accum_bus),

        .safety_fault(safety_fault),
        .done(done),
        .cycle_count(cycle_count),
        .instruction_count(instruction_count),
        .branch_count(branch_count),
        .selected_lane(selected_lane)
    );

    task load_instruction;
        input [7:0] address;
        input [31:0] data;
        begin
            @(negedge clk);
            imem_write = 1;
            imem_address = address;
            imem_data = data;

            @(negedge clk);
            imem_write = 0;
        end
    endtask

    initial begin
        $display("");
        $display("DREAM GPU v0.8 MEMORY VERIFICATION");
        $display("=================================");

        repeat (3) @(negedge clk);
        reset = 0;

        // Each lane executes the same program:
        // 0: Load its lane ID into accumulator.
        // 1: Add 10.
        // 2: Store accumulator at private bank offset 4.
        // 3: Clear accumulator.
        // 4: Load from private bank offset 4.
        // 5: Add 1.
        // 6: Halt.

        load_instruction(0, 32'h80000000);
        load_instruction(1, 32'h2000000A);
        load_instruction(2, 32'hA0000004);
        load_instruction(3, 32'h10000000);
        load_instruction(4, 32'h90000004);
        load_instruction(5, 32'h20000001);
        load_instruction(6, 32'h70000000);

        $display("PASS: program loaded");

        run_enable = 1;

        // Allow enough cycles for all four lanes to finish.
        repeat (80) @(negedge clk);

        if (!done)
            $fatal(1, "FAIL: lanes did not all halt");

        $display("PASS: all lanes halted");

        if (safety_fault)
            $fatal(1, "FAIL: unexpected safety fault");

        $display("PASS: no unexpected safety fault");

        if (accum_bus[31:0] !== 32'd11)
            $fatal(1, "FAIL: lane 0 accumulator");

        if (accum_bus[63:32] !== 32'd12)
            $fatal(1, "FAIL: lane 1 accumulator");

        if (accum_bus[95:64] !== 32'd13)
            $fatal(1, "FAIL: lane 2 accumulator");

        if (accum_bus[127:96] !== 32'd14)
            $fatal(1, "FAIL: lane 3 accumulator");

        $display("PASS lane 0 accumulator = %0d", accum_bus[31:0]);
        $display("PASS lane 1 accumulator = %0d", accum_bus[63:32]);
        $display("PASS lane 2 accumulator = %0d", accum_bus[95:64]);
        $display("PASS lane 3 accumulator = %0d", accum_bus[127:96]);

        // Verify each lane wrote to its own memory bank.
        if (dut.data_memory[4] !== 32'd10)
            $fatal(1, "FAIL: lane 0 memory bank");

        if (dut.data_memory[68] !== 32'd11)
            $fatal(1, "FAIL: lane 1 memory bank");

        if (dut.data_memory[132] !== 32'd12)
            $fatal(1, "FAIL: lane 2 memory bank");

        if (dut.data_memory[196] !== 32'd13)
            $fatal(1, "FAIL: lane 3 memory bank");

        $display("PASS: lane 0 private memory = 10");
        $display("PASS: lane 1 private memory = 11");
        $display("PASS: lane 2 private memory = 12");
        $display("PASS: lane 3 private memory = 13");

        if (instruction_count !== 32'd28)
            $fatal(1, "FAIL: unexpected instruction count");

        $display("PASS: instruction count = %0d", instruction_count);

        if (branch_count !== 32'd0)
            $fatal(1, "FAIL: unexpected branch count");

        $display("PASS: branch count = 0");

        $display("");
        $display("Cycles: %0d", cycle_count);
        $display("Instructions: %0d", instruction_count);
        $display("Branches: %0d", branch_count);
        $display("");
        $display("DREAM GPU v0.8 MEMORY TESTS PASS");
        $display("");

        $finish;
    end

endmodule
