`timescale 1ns/1ps

module tb_dream_gpu_v10_maci;
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
    wire [3:0] fault_code;
    wire done;
    wire [31:0] cycle_count, instruction_count, branch_count;
    wire [1:0] selected_lane;

    always #5 clk = ~clk;

    dream_gpu_engine_v10 dut (
        .clk(clk), .reset(reset), .run_enable(run_enable),
        .imem_write(imem_write), .imem_address(imem_address), .imem_data(imem_data),
        .lane_mask(lane_mask), .pc_bus(pc_bus), .accum_bus(accum_bus),
        .safety_fault(safety_fault), .fault_code(fault_code), .done(done),
        .cycle_count(cycle_count), .instruction_count(instruction_count),
        .branch_count(branch_count), .selected_lane(selected_lane)
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

    task reset_engine;
        begin
            run_enable = 0;
            reset = 1;
            repeat (3) @(negedge clk);
            reset = 0;
        end
    endtask

    initial begin
        $display("DREAM GPU v1.0 SIGNED MACI VERIFICATION");
        repeat (3) @(negedge clk);
        reset = 0;

        // Positive multiply-accumulate: (lane_id + 2) * 3.
        load_instruction(0, 32'h80000000); // LID
        load_instruction(1, 32'h20000002); // ADDI 2
        load_instruction(2, 32'hA0000004); // ST private offset 4
        load_instruction(3, 32'h10000000); // MOVI 0
        load_instruction(4, 32'hB00000C4); // MACI immediate 3, offset 4
        load_instruction(5, 32'h70000000); // HALT
        run_enable = 1;
        repeat (100) @(negedge clk);
        if (!done || safety_fault) $fatal(1, "FAIL: positive MACI execution/fault");
        if (accum_bus[31:0] !== 32'd6 ||
            accum_bus[63:32] !== 32'd9 ||
            accum_bus[95:64] !== 32'd12 ||
            accum_bus[127:96] !== 32'd15)
            $fatal(1, "FAIL: positive MACI results %0d %0d %0d %0d",
                accum_bus[31:0], accum_bus[63:32], accum_bus[95:64], accum_bus[127:96]);
        $display("PASS: positive MACI results = 6, 9, 12, 15");

        // Negative x negative: (-2) * (-3) = +6 for every lane.
        reset_engine();
        load_instruction(0, 32'h1000FFFE); // MOVI -2
        load_instruction(1, 32'hA0000004); // ST private offset 4
        load_instruction(2, 32'h10000000); // MOVI 0
        load_instruction(3, 32'hB03FFF44); // MACI immediate -3, offset 4
        load_instruction(4, 32'h70000000); // HALT
        run_enable = 1;
        repeat (100) @(negedge clk);
        if (!done || safety_fault) $fatal(1, "FAIL: signed MACI execution/fault");
        if (accum_bus[31:0] !== 32'd6 ||
            accum_bus[63:32] !== 32'd6 ||
            accum_bus[95:64] !== 32'd6 ||
            accum_bus[127:96] !== 32'd6)
            $fatal(1, "FAIL: signed MACI results %0d %0d %0d %0d",
                accum_bus[31:0], accum_bus[63:32], accum_bus[95:64], accum_bus[127:96]);
        $display("PASS: signed MACI negative operands = 6, 6, 6, 6");
        $display("DREAM GPU v1.0 SIGNED MACI TEST PASS");
        $finish;
    end
endmodule
