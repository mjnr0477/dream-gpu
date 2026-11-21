`timescale 1ns/1ps

module tb_dream_gpu_v09;

    reg clk = 0;
    always #5 clk = ~clk;

    // Main reliability-test engine
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
    wire [31:0] cycle_count;
    wire [31:0] instruction_count;
    wire [31:0] branch_count;
    wire [1:0] selected_lane;

    dream_gpu_engine_v09 #(
        .WATCHDOG_LIMIT(1000)
    ) dut (
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
        .fault_code(fault_code),
        .done(done),
        .cycle_count(cycle_count),
        .instruction_count(instruction_count),
        .branch_count(branch_count),
        .selected_lane(selected_lane)
    );

    // Independent watchdog-test engine
    reg wd_reset = 1;
    reg wd_run_enable = 0;
    reg wd_imem_write = 0;
    reg [7:0] wd_imem_address = 0;
    reg [31:0] wd_imem_data = 0;

    wire [3:0] wd_lane_mask;
    wire [35:0] wd_pc_bus;
    wire [127:0] wd_accum_bus;
    wire wd_safety_fault;
    wire [3:0] wd_fault_code;
    wire wd_done;
    wire [31:0] wd_cycle_count;
    wire [31:0] wd_instruction_count;
    wire [31:0] wd_branch_count;
    wire [1:0] wd_selected_lane;

    dream_gpu_engine_v09 #(
        .WATCHDOG_LIMIT(2)
    ) watchdog_dut (
        .clk(clk),
        .reset(wd_reset),
        .run_enable(wd_run_enable),
        .imem_write(wd_imem_write),
        .imem_address(wd_imem_address),
        .imem_data(wd_imem_data),
        .lane_mask(wd_lane_mask),
        .pc_bus(wd_pc_bus),
        .accum_bus(wd_accum_bus),
        .safety_fault(wd_safety_fault),
        .fault_code(wd_fault_code),
        .done(wd_done),
        .cycle_count(wd_cycle_count),
        .instruction_count(wd_instruction_count),
        .branch_count(wd_branch_count),
        .selected_lane(wd_selected_lane)
    );

    task reset_main;
        begin
            run_enable = 0;
            reset = 1;
            repeat (2) @(negedge clk);
            reset = 0;
            @(negedge clk);
        end
    endtask

    task load_main;
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

    task check_fault;
        input [3:0] expected_code;
        input [255:0] test_name;
        begin
            if (!safety_fault)
                $fatal(1, "FAIL: %0s did not trigger", test_name);

            if (fault_code !== expected_code)
                $fatal(1, "FAIL: %0s fault code=%0d expected=%0d",
                       test_name, fault_code, expected_code);

            $display("PASS: %0s fault code=%0d",
                     test_name, fault_code);
        end
    endtask

    initial begin
        $display("");
        $display("DREAM GPU v0.9 RELIABILITY VERIFICATION");
        $display("======================================");

        // TEST 1: Invalid instruction
        reset_main();
        load_main(0, 32'hF0000000);
        run_enable = 1;
        repeat (4) @(negedge clk);
        check_fault(4, "invalid instruction");

        // TEST 2: Invalid jump target
        reset_main();
        load_main(0, 32'h60000100);
        run_enable = 1;
        repeat (4) @(negedge clk);
        check_fault(3, "invalid jump target");

        // TEST 3: Out-of-range program counter
        reset_main();
        load_main(0, 32'h00000000);

        force dut.processor.pc[0] = 9'd256;
        run_enable = 1;
        repeat (3) @(negedge clk);
        check_fault(2, "out-of-range program counter");
        release dut.processor.pc[0];

        // TEST 4: Reset and successful recovery
        reset_main();

        load_main(0, 32'h10000007);
        load_main(1, 32'h20000004);
        load_main(2, 32'h70000000);

        run_enable = 1;
        repeat (30) @(negedge clk);

        if (safety_fault)
            $fatal(1, "FAIL: fault remained after reset");

        if (fault_code !== 4'd0)
            $fatal(1, "FAIL: fault code did not clear");

        if (!done)
            $fatal(1, "FAIL: recovery program did not finish");

        if (accum_bus[31:0] !== 32'd11 ||
            accum_bus[63:32] !== 32'd11 ||
            accum_bus[95:64] !== 32'd11 ||
            accum_bus[127:96] !== 32'd11)
            $fatal(1, "FAIL: recovery accumulator values");

        $display("PASS: reset clears previous fault");
        $display("PASS: all lanes recover and execute");
        $display("PASS: recovery accumulators = 11");

        // TEST 5: Independent watchdog engine
        wd_reset = 1;
        wd_run_enable = 0;
        repeat (2) @(negedge clk);
        wd_reset = 0;

        @(negedge clk);
        wd_imem_write = 1;
        wd_imem_address = 0;
        wd_imem_data = 32'h00000000;

        @(negedge clk);
        wd_imem_write = 0;
        wd_run_enable = 1;

        repeat (8) @(negedge clk);

        if (!wd_safety_fault)
            $fatal(1, "FAIL: watchdog did not trigger");

        if (wd_fault_code !== 4'd1)
            $fatal(1, "FAIL: watchdog fault code incorrect");

        $display("PASS: watchdog timeout fault code=1");

        $display("");
        $display("Main engine cycles: %0d", cycle_count);
        $display("Main engine instructions: %0d", instruction_count);
        $display("Main engine branches: %0d", branch_count);
        $display("");
        $display("DREAM GPU v0.9 RELIABILITY TESTS PASS");
        $display("");

        $finish;
    end

endmodule
