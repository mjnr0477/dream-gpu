`timescale 1ns/1ps

module tb_dream_gpu_v07;

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

    integer errors = 0;
    integer timeout_count = 0;

    always #5 clk = ~clk;

    dream_gpu_engine_v07 #(
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
                $display("FAIL lane %0d expected %0d got %0d",
                    lane, expected, accum_bus[lane*32 +: 32]);
                errors = errors + 1;
            end
            else begin
                $display("PASS lane %0d accumulator=%0d",
                    lane, accum_bus[lane*32 +: 32]);
            end
        end
    endtask

    initial begin
        $dumpfile("simulation/dream_gpu_v07.vcd");
        $dumpvars(0, tb_dream_gpu_v07);

        $display("");
        $display("DREAM GPU v0.7 DIVERGENT EXECUTION TEST");
        $display("======================================");

        repeat (3) @(negedge clk);
        reset = 0;

        // Program:
        // 0: LID
        // 1: BRZ +3       lane 0 branches to address 5
        // 2: ADDI 10
        // 3: ADDI 5
        // 4: JMP 6        lanes 1-3 branch to address 6
        // 5: HALT          lane 0
        // 6: HALT          lanes 1-3

        write_instruction(0, 32'h80000000);
        write_instruction(1, 32'h50000003);
        write_instruction(2, 32'h2000000A);
        write_instruction(3, 32'h20000005);
        write_instruction(4, 32'h60000006);
        write_instruction(5, 32'h70000000);
        write_instruction(6, 32'h70000000);

        run_enable = 1;

        // Wait for lane 0 to halt while other lanes remain active.
        while (lane_mask[0] && timeout_count < 100) begin
            @(negedge clk);
            timeout_count = timeout_count + 1;
        end

        if (lane_mask[0]) begin
            $display("FAIL: lane 0 did not halt in time");
            errors = errors + 1;
        end
        else begin
            $display("PASS: lane 0 halted independently");
        end

        if (lane_mask[3:1] !== 3'b111) begin
            $display("FAIL: lanes 1-3 did not remain active");
            errors = errors + 1;
        end
        else begin
            $display("PASS: lanes 1-3 continued independently");
        end

        timeout_count = 0;
        while (!done && !safety_fault && timeout_count < 100) begin
            @(negedge clk);
            timeout_count = timeout_count + 1;
        end

        if (!done) begin
            $display("FAIL: processor did not finish");
            errors = errors + 1;
        end
        else begin
            $display("PASS: all lanes halted");
        end

        check_value(0, 32'd0);
        check_value(1, 32'd16);
        check_value(2, 32'd17);
        check_value(3, 32'd18);

        if (branch_count !== 32'd4) begin
            $display("FAIL: branch count expected 4 got %0d",
                branch_count);
            errors = errors + 1;
        end
        else begin
            $display("PASS: branch count = 4");
        end

        if (instruction_count !== 32'd21) begin
            $display("FAIL: instruction count expected 21 got %0d",
                instruction_count);
            errors = errors + 1;
        end
        else begin
            $display("PASS: instruction count = 21");
        end

        if (safety_fault) begin
            $display("FAIL: unexpected safety fault");
            errors = errors + 1;
        end
        else begin
            $display("PASS: no unexpected safety fault");
        end

        $display("");
        $display("Cycles: %0d", cycle_count);
        $display("Instructions: %0d", instruction_count);
        $display("Branches: %0d", branch_count);

        if (errors == 0)
            $display("DREAM GPU v0.7 DIVERGENT TESTS PASS");
        else
            $display("DREAM GPU v0.7 TESTS FAILED: %0d", errors);

        $finish;
    end

endmodule
