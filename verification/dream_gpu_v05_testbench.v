`timescale 1ns/1ps

module dream_gpu_v05_testbench;

    reg clk;
    reg rst;
    reg run;

    reg program_we;
    reg [7:0] program_addr;
    reg [31:0] program_wdata;

    reg host_we;
    reg [1:0] host_lane;
    reg [2:0] host_addr;
    reg signed [15:0] host_wdata;

    reg [1:0] debug_lane;
    reg [2:0] debug_addr;

    wire signed [15:0] debug_rdata;
    wire [7:0] program_counter;
    wire program_done;
    wire busy;

    integer errors;
    integer cycles;

    dream_gpu_program_engine dut(
        .clk(clk),
        .rst(rst),
        .run(run),

        .program_we(program_we),
        .program_addr(program_addr),
        .program_wdata(program_wdata),

        .host_we(host_we),
        .host_lane(host_lane),
        .host_addr(host_addr),
        .host_wdata(host_wdata),

        .debug_lane(debug_lane),
        .debug_addr(debug_addr),
        .debug_rdata(debug_rdata),

        .program_counter(program_counter),
        .program_done(program_done),
        .busy(busy)
    );

    always #5 clk = ~clk;

    task write_instruction;
        input [7:0] address;
        input [31:0] instruction;
        begin
            @(negedge clk);
            program_we = 1'b1;
            program_addr = address;
            program_wdata = instruction;

            @(posedge clk);
            #1;

            @(negedge clk);
            program_we = 1'b0;
        end
    endtask

    task check_register;
        input [1:0] lane;
        input [2:0] address;
        input signed [15:0] expected;
        begin
            @(negedge clk);
            debug_lane = lane;
            debug_addr = address;
            #1;

            if (debug_rdata !== expected) begin
                $display(
                    "FAIL: lane=%0d register=%0d expected=%0d actual=%0d",
                    lane, address, expected, debug_rdata
                );
                errors = errors + 1;
            end else begin
                $display(
                    "PASS: lane=%0d register=%0d value=%0d",
                    lane, address, debug_rdata
                );
            end
        end
    endtask

    initial begin

        clk = 0;
        rst = 1;
        run = 0;

        program_we = 0;
        program_addr = 0;
        program_wdata = 0;

        host_we = 0;
        host_lane = 0;
        host_addr = 0;
        host_wdata = 0;

        debug_lane = 0;
        debug_addr = 0;

        errors = 0;
        cycles = 0;

        $dumpfile("simulation/dream_gpu_v05.vcd");
        $dumpvars(0, dream_gpu_v05_testbench);

        $display("");
        $display("DREAM GPU v0.5 PROGRAM ENGINE TEST");
        $display("===================================");

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 0;

        // Instruction encoding:
        // {opcode[3:0], rd[2:0], ra[2:0], rb[2:0], reserved[2:0], immediate[15:0]}

        // 0: MOVI r1, 10
        write_instruction(0, {4'h5, 3'd1, 3'd0, 3'd0, 3'd0, 16'd10});

        // 1: MOVI r2, 5
        write_instruction(1, {4'h5, 3'd2, 3'd0, 3'd0, 3'd0, 16'd5});

        // 2: ADD r3, r1, r2 -> 15
        write_instruction(2, {4'h1, 3'd3, 3'd1, 3'd2, 3'd0, 16'd0});

        // 3: STORE memory[r1], r3
        write_instruction(3, {4'h7, 3'd0, 3'd1, 3'd3, 3'd0, 16'd0});

        // 4: MOVI r4, 0
        write_instruction(4, {4'h5, 3'd4, 3'd0, 3'd0, 3'd0, 16'd0});

        // 5: LOAD r4, memory[r1]
        write_instruction(5, {4'h6, 3'd4, 3'd1, 3'd0, 3'd0, 16'd0});

        // 6: ADD r5, r4, r2 -> 20
        write_instruction(6, {4'h1, 3'd5, 3'd4, 3'd2, 3'd0, 16'd0});

        // 7: MOVI r6, 0
        write_instruction(7, {4'h5, 3'd6, 3'd0, 3'd0, 3'd0, 16'd0});

        // 8: BEQZ r6, 10 (taken; skips instruction 9)
        write_instruction(8, {4'h9, 3'd0, 3'd6, 3'd0, 3'd0, 16'd10});

        // 9: MOVI r7, 99 (must be skipped)
        write_instruction(9, {4'h5, 3'd7, 3'd0, 3'd0, 3'd0, 16'd99});

        // 10: MOVI r7, 77
        write_instruction(10, {4'h5, 3'd7, 3'd0, 3'd0, 3'd0, 16'd77});

        // 11: BEQZ r5, 13 (not taken because r5=20)
        write_instruction(11, {4'h9, 3'd0, 3'd5, 3'd0, 3'd0, 16'd13});

        // 12: MOVI r0, 1 (must execute)
        write_instruction(12, {4'h5, 3'd0, 3'd0, 3'd0, 3'd0, 16'd1});

        // 13: HALT
        write_instruction(13, {4'hF, 3'd0, 3'd0, 3'd0, 3'd0, 16'd0});

        $display("PASS: 14 program words loaded");

        // Start autonomous execution.
        @(negedge clk);
        run = 1;

        @(negedge clk);
        run = 0;

        // Wait for completion with a hard timeout.
        cycles = 0;

        while (program_done !== 1'b1 && cycles < 200) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end

        if (program_done !== 1'b1) begin
            $display("FAIL: program execution timeout");
            errors = errors + 1;
        end else begin
            $display("PASS: program completed in %0d cycles", cycles);
        end

        if (busy !== 1'b0) begin
            $display("FAIL: processor still busy after HALT");
            errors = errors + 1;
        end else begin
            $display("PASS: processor stopped after HALT");
        end

        // Verify results across all four SIMD lanes.
        check_register(0, 3, 16'sd15);
        check_register(1, 3, 16'sd15);
        check_register(2, 3, 16'sd15);
        check_register(3, 3, 16'sd15);

        check_register(0, 4, 16'sd15);
        check_register(1, 4, 16'sd15);
        check_register(2, 4, 16'sd15);
        check_register(3, 4, 16'sd15);

        check_register(0, 5, 16'sd20);
        check_register(1, 5, 16'sd20);
        check_register(2, 5, 16'sd20);
        check_register(3, 5, 16'sd20);

        check_register(0, 7, 16'sd77);
        check_register(1, 7, 16'sd77);
        check_register(2, 7, 16'sd77);
        check_register(3, 7, 16'sd77);

        check_register(0, 0, 16'sd1);
        check_register(1, 0, 16'sd1);
        check_register(2, 0, 16'sd1);
        check_register(3, 0, 16'sd1);

        $display("");
        $display("===================================");

        if (errors == 0) begin
            $display("ALL DREAM GPU v0.5 TESTS PASSED");
        end else begin
            $display("TOTAL FAILURES: %0d", errors);
            $fatal(1, "DREAM GPU v0.5 verification failed");
        end

        $display("===================================");
        $finish;
    end

endmodule
