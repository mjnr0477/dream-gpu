`timescale 1ns/1ps

module tb_dream_gpu_v06;

    reg clk = 0;
    reg reset = 1;

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

    integer errors = 0;
    integer cycles = 0;

    always #5 clk = ~clk;

    dream_gpu_engine_v06 #(
        .WATCHDOG_LIMIT(1000)
    ) dut (
        .clk(clk),
        .reset(reset),

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

    task write_instruction;
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

    task check_value;
        input integer lane;
        input [31:0] expected;
        begin
            if (accum_bus[lane*32 +: 32] !== expected) begin
                $display(
                    "FAIL lane=%0d expected=%0d actual=%0d",
                    lane,
                    expected,
                    accum_bus[lane*32 +: 32]
                );
                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS lane=%0d accumulator=%0d",
                    lane,
                    accum_bus[lane*32 +: 32]
                );
            end
        end
    endtask

    initial begin

        $dumpfile("simulation/dream_gpu_v06.vcd");
        $dumpvars(0, tb_dream_gpu_v06);

        $display("");
        $display("DREAM GPU v0.6 VERIFICATION");
        $display("===========================");

        repeat (3) @(negedge clk);
        reset = 0;

        // Program: MOVI 5, ADDI 7, HALT
        write_instruction(0, 32'h10000005);
        write_instruction(1, 32'h20000007);
        write_instruction(2, 32'h70000000);

        // Every lane starts at address zero.
        repeat (40) @(negedge clk);

        check_value(0, 32'd12);
        check_value(1, 32'd12);
        check_value(2, 32'd12);
        check_value(3, 32'd12);

        if (!done) begin
            $display("FAIL: processor did not halt all lanes");
            errors = errors + 1;
        end
        else begin
            $display("PASS: all lanes halted");
        end

        if (safety_fault) begin
            $display("FAIL: unexpected safety fault");
            errors = errors + 1;
        end
        else begin
            $display("PASS: no unexpected safety fault");
        end

        if (instruction_count != 12) begin
            $display(
                "FAIL: instruction count expected 12 actual %0d",
                instruction_count
            );
            errors = errors + 1;
        end
        else begin
            $display("PASS: instruction count = 12");
        end

        $display("");
        $display("Cycles: %0d", cycle_count);
        $display("Instructions: %0d", instruction_count);
        $display("Branches: %0d", branch_count);

        if (errors == 0)
            $display("DREAM GPU v0.6 BASIC TESTS PASS");
        else
            $display("DREAM GPU v0.6 TESTS FAILED: %0d", errors);

        $finish;
    end

endmodule
