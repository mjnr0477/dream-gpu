`timescale 1ns/1ps

module dream_gpu_v04_testbench;

reg clk, rst;
reg input_valid;
reg [3:0] opcode;
reg [2:0] rd, ra, rb;
reg signed [15:0] immediate;

reg host_we;
reg [1:0] host_lane;
reg [2:0] host_addr;
reg signed [15:0] host_wdata;

reg [1:0] debug_lane;
reg [2:0] debug_addr;
wire signed [15:0] debug_rdata;

reg [1:0] debug_acc_lane;
reg [2:0] debug_acc_addr;
wire signed [39:0] debug_acc;

wire done;
integer errors;

dream_gpu_core_v04 dut(
    .clk(clk),
    .rst(rst),
    .input_valid(input_valid),
    .opcode(opcode),
    .rd(rd),
    .ra(ra),
    .rb(rb),
    .immediate(immediate),
    .host_we(host_we),
    .host_lane(host_lane),
    .host_addr(host_addr),
    .host_wdata(host_wdata),
    .debug_lane(debug_lane),
    .debug_addr(debug_addr),
    .debug_rdata(debug_rdata),
    .debug_acc_lane(debug_acc_lane),
    .debug_acc_addr(debug_acc_addr),
    .debug_acc(debug_acc),
    .done(done)
);

always #5 clk = ~clk;

task host_write;
    input [1:0] lane;
    input [2:0] address;
    input signed [15:0] value;
    begin
        @(negedge clk);
        host_we = 1;
        host_lane = lane;
        host_addr = address;
        host_wdata = value;
        @(posedge clk);
        #1;
        @(negedge clk);
        host_we = 0;
    end
endtask

task issue_instruction;
    input [3:0] op;
    input [2:0] dest;
    input [2:0] src_a;
    input [2:0] src_b;
    begin
        @(negedge clk);
        opcode = op;
        rd = dest;
        ra = src_a;
        rb = src_b;
        input_valid = 1;
        @(posedge clk);
        #1;
        if (done !== 1'b1) begin
            $display("FAIL: instruction %h did not complete", op);
            errors = errors + 1;
        end else begin
            $display("PASS: instruction %h completed", op);
        end
        @(negedge clk);
        input_valid = 0;
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
    input_valid = 0;
    opcode = 0;
    rd = 0;
    ra = 0;
    rb = 0;
    immediate = 0;
    host_we = 0;
    host_lane = 0;
    host_addr = 0;
    host_wdata = 0;
    debug_lane = 0;
    debug_addr = 0;
    debug_acc_lane = 0;
    debug_acc_addr = 0;
    errors = 0;

    $dumpfile("simulation/dream_gpu_v04.vcd");
    $dumpvars(0, dream_gpu_v04_testbench);

    $display("");
    $display("DREAM GPU v0.4 PROCESSOR/MEMORY TEST");
    $display("====================================");

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 0;

    // Initialise four independent lane addresses and values.
    host_write(0, 1, 16'd10);
    host_write(1, 1, 16'd20);
    host_write(2, 1, 16'd30);
    host_write(3, 1, 16'd40);

    host_write(0, 2, 16'sd111);
    host_write(1, 2, -16'sd222);
    host_write(2, 2, 16'sd333);
    host_write(3, 2, -16'sd444);

    // Store each lane's register 2 at the address in register 1.
    issue_instruction(4'h7, 0, 1, 2);

    // Clear the destination registers before loading.
    host_write(0, 3, 0);
    host_write(1, 3, 0);
    host_write(2, 3, 0);
    host_write(3, 3, 0);

    // Load memory contents into register 3 in every lane.
    issue_instruction(4'h6, 3, 1, 0);

    check_register(0, 3, 16'sd111);
    check_register(1, 3, -16'sd222);
    check_register(2, 3, 16'sd333);
    check_register(3, 3, -16'sd444);

    // Check that existing arithmetic still works.
    host_write(0, 4, 16'd7);
    host_write(1, 4, 16'd7);
    host_write(2, 4, 16'd7);
    host_write(3, 4, 16'd7);

    issue_instruction(4'h1, 5, 3, 4);

    check_register(0, 5, 16'sd118);
    check_register(1, 5, -16'sd215);
    check_register(2, 5, 16'sd340);
    check_register(3, 5, -16'sd437);

    $display("");
    $display("====================================");

    if (errors == 0) begin
        $display("ALL DREAM GPU v0.4 TESTS PASSED");
    end else begin
        $display("TOTAL FAILURES: %0d", errors);
        $fatal(1, "DREAM GPU v0.4 verification failed");
    end

    $display("====================================");
    $finish;
end

endmodule
