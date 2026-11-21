`timescale 1ns/1ps
module tb_dream_gpu_v12_host;
  reg clk=0,reset=1,host_valid=0,host_write=0;
  reg [7:0] host_addr=0;
  reg [31:0] host_wdata=0;
  wire host_ready,host_error,busy,done,safety_fault;
  wire [31:0] host_rdata;
  wire [3:0] halted_mask;
  integer k;
  always #5 clk=~clk;

  dream_gpu_host_v12 #(.WATCHDOG_LIMIT(1000)) dut(
    .clk(clk),.reset(reset),.host_valid(host_valid),.host_write(host_write),
    .host_addr(host_addr),.host_wdata(host_wdata),.host_ready(host_ready),
    .host_rdata(host_rdata),.host_error(host_error),.busy(busy),.done(done),
    .safety_fault(safety_fault),.halted_mask(halted_mask)
  );

  task write_reg(input [7:0] a,input [31:0] d);
    begin
      @(negedge clk); host_valid=1; host_write=1; host_addr=a; host_wdata=d;
      @(negedge clk); host_valid=0; host_write=0;
    end
  endtask

  task read_check(input [7:0] a,input [31:0] expected);
    begin
      @(negedge clk); host_valid=1; host_write=0; host_addr=a; #1;
      if(!host_ready || host_error || host_rdata!==expected)
        $fatal(1,"FAIL: host read addr=%h expected=%h got=%h",a,expected,host_rdata);
      host_valid=0;
    end
  endtask

  task load_instruction(input [7:0] a,input [31:0] d);
    begin
      write_reg(8'h20,a);
      write_reg(8'h24,d);
      write_reg(8'h28,32'd1);
    end
  endtask

  task load_private_word(input [1:0] lane,input [5:0] offset,input [31:0] d);
    begin
      write_reg(8'h30,{24'b0,lane,offset});
      write_reg(8'h34,d);
      write_reg(8'h38,32'd1);
    end
  endtask

  initial begin
    $display("DREAM GPU v1.2 HOST INTERFACE VERIFICATION");
    repeat(3) @(negedge clk); reset=0;
    if(!host_ready && host_valid) $fatal(1,"FAIL: host interface not ready");

    // Load a lane-private data value through the host bus for every lane.
    load_private_word(0,7,10);
    load_private_word(1,7,20);
    load_private_word(2,7,30);
    load_private_word(3,7,40);
    read_check(8'h3C,40);

    // Load the same instruction stream into shared instruction memory.
    load_instruction(0,32'h90000007); // LD [7]
    load_instruction(1,32'h20000001); // ADDI 1
    load_instruction(2,32'h70000000); // HALT

    write_reg(8'h00,1);
    wait(done); #1;
    if(safety_fault) $fatal(1,"FAIL: host-launched program faulted");
    if(halted_mask!==4'b1111) $fatal(1,"FAIL: not all lanes halted");
    read_check(8'h40,11);
    read_check(8'h44,21);
    read_check(8'h48,31);
    read_check(8'h4C,41);
    read_check(8'h0C,3);
    read_check(8'h10,12);
    read_check(8'h04,32'h0000003C);
    $display("PASS: host loaded shared instructions");
    $display("PASS: host wrote and read lane-private memory");
    $display("PASS: host launched program and read four lane results");
    $display("PASS: host status and performance counters readable");
    $display("DREAM GPU v1.2 HOST INTERFACE TEST PASS");
    $finish;
  end
endmodule
