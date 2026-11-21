`timescale 1ns/1ps

module dream_gpu_v02_testbench;

reg clk=0;
reg rst=0;

reg input_valid=0;
reg [3:0] opcode=0;
reg [2:0] rd=0,ra=0,rb=0;
reg signed [15:0] immediate=0;

reg host_we=0;
reg [1:0] host_lane=0;
reg [2:0] host_addr=0;
reg signed [15:0] host_wdata=0;

reg [1:0] debug_lane=0;
reg [2:0] debug_addr=0;

reg [1:0] debug_acc_lane=0;
reg [2:0] debug_acc_addr=0;

wire signed [15:0] debug_rdata;
wire signed [39:0] debug_acc;
wire done;

dream_gpu_core dut(
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

always #5 clk=~clk;

task write_register;
input [1:0] lane;
input [2:0] address;
input signed [15:0] value;
begin
    @(negedge clk);
    host_lane=lane;
    host_addr=address;
    host_wdata=value;
    host_we=1;

    @(posedge clk);
    #1;

    @(negedge clk);
    host_we=0;
end
endtask

task issue_instruction;
input [3:0] op;
input [2:0] destination;
input [2:0] source_a;
input [2:0] source_b;
input signed [15:0] imm;
begin
    @(negedge clk);

    opcode=op;
    rd=destination;
    ra=source_a;
    rb=source_b;
    immediate=imm;
    input_valid=1;

    @(posedge clk);
    #1;

    if(done !== 1'b1)
        $fatal(1,"INSTRUCTION COMPLETION FAILED");

    @(negedge clk);
    input_valid=0;
end
endtask

task check_register;
input [1:0] lane;
input [2:0] address;
input signed [15:0] expected;
begin
    debug_lane=lane;
    debug_addr=address;
    #1;

    if(debug_rdata !== expected)
        $fatal(1,"REGISTER FAILURE lane=%0d addr=%0d actual=%0d expected=%0d",
               lane,address,debug_rdata,expected);

    $display("REGISTER PASS lane=%0d address=%0d value=%0d",
             lane,address,debug_rdata);
end
endtask

task check_accumulator;
input [1:0] lane;
input [2:0] address;
input signed [39:0] expected;
begin
    debug_acc_lane=lane;
    debug_acc_addr=address;
    #1;

    if(debug_acc !== expected)
        $fatal(1,"ACCUMULATOR FAILURE lane=%0d actual=%0d expected=%0d",
               lane,debug_acc,expected);

    $display("ACCUMULATOR PASS lane=%0d value=%0d",
             lane,debug_acc);
end
endtask

integer k;

initial begin

    $dumpfile("simulation/dream_gpu_v02.vcd");
    $dumpvars(0,dream_gpu_v02_testbench);

    $display("");
    $display("DREAM GPU v0.2 VERIFICATION");
    $display("===========================");

    // Reset
    rst=1;
    repeat(2) @(posedge clk);
    @(negedge clk);
    rst=0;

    // Load distinct values into all four lanes
    write_register(0,1,3);
    write_register(0,2,4);

    write_register(1,1,-2);
    write_register(1,2,5);

    write_register(2,1,7);
    write_register(2,2,-3);

    write_register(3,1,0);
    write_register(3,2,9);

    // MAC
    issue_instruction(4'h4,0,1,2,0);

    check_accumulator(0,0,12);
    check_accumulator(1,0,-10);
    check_accumulator(2,0,-21);
    check_accumulator(3,0,0);

    // Repeated MAC
    issue_instruction(4'h4,0,1,2,0);

    check_accumulator(0,0,24);
    check_accumulator(1,0,-20);
    check_accumulator(2,0,-42);
    check_accumulator(3,0,0);

    // ADD
    issue_instruction(4'h1,3,1,2,0);

    check_register(0,3,7);
    check_register(1,3,3);
    check_register(2,3,4);
    check_register(3,3,9);

    // SUB
    issue_instruction(4'h2,5,1,2,0);

    check_register(0,5,-1);
    check_register(1,5,-7);
    check_register(2,5,10);
    check_register(3,5,-9);

    // MUL
    issue_instruction(4'h3,6,1,2,0);

    check_register(0,6,12);
    check_register(1,6,-10);
    check_register(2,6,-21);
    check_register(3,6,0);

    // MOVI
    issue_instruction(4'h5,7,0,0,123);

    for(k=0;k<4;k=k+1)
        check_register(k,7,123);

    // Invalid instruction must not execute
    @(negedge clk);
    opcode=4'hF;
    input_valid=1;

    @(posedge clk);
    #1;

    if(done !== 1'b0)
        $fatal(1,"INVALID INSTRUCTION WAS ACCEPTED");

    @(negedge clk);
    input_valid=0;

    // Reset all register and accumulator banks
    rst=1;
    @(posedge clk);
    #1;
    rst=0;

    check_register(0,1,0);
    check_accumulator(0,0,0);

    $display("");
    $display("==================================");
    $display("ALL DREAM GPU v0.2 TESTS PASSED");
    $display("==================================");

    $finish;

end

endmodule
