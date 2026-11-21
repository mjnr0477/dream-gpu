`timescale 1ns/1ps

module mac4_testbench;

reg clk=0,rst=0,enable=0,clear=0;
reg signed [15:0] a0,b0,a1,b1,a2,b2,a3,b3;
wire signed [39:0] acc0,acc1,acc2,acc3;

dream_gpu_mac4 dut (
.clk(clk),.rst(rst),.enable(enable),.clear(clear),
.a0(a0),.b0(b0),.a1(a1),.b1(b1),
.a2(a2),.b2(b2),.a3(a3),.b3(b3),
.acc0(acc0),.acc1(acc1),.acc2(acc2),.acc3(acc3)
);

always #5 clk=~clk;

task check;
input signed [39:0] e0,e1,e2,e3;
begin
if(acc0 !== e0 || acc1 !== e1 ||
   acc2 !== e2 || acc3 !== e3)
$fatal(1,"TEST FAILED");
else $display("PASS: %0d %0d %0d %0d",acc0,acc1,acc2,acc3);
end
endtask

initial begin
$dumpfile("simulation/mac4.vcd");
$dumpvars(0,mac4_testbench);

a0=3;b0=4;
a1=-2;b1=5;
a2=7;b2=-3;
a3=0;b3=9;

rst=1;
#10;
check(0,0,0,0);

rst=0;enable=1;
#10;
check(12,-10,-21,0);

#10;
check(24,-20,-42,0);

enable=0;
#10;
check(24,-20,-42,0);

clear=1;
#10;
check(0,0,0,0);

clear=0;enable=1;
#10;
check(12,-10,-21,0);

$display("ALL DREAM GPU TESTS PASSED");
$finish;
end
endmodule
