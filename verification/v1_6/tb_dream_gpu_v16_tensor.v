`timescale 1ns/1ps
module tb_dream_gpu_v16_tensor;
    reg clk=0,reset=1,host_valid=0,host_write=0;
    reg [7:0] host_addr=0;
    reg [31:0] host_wdata=0;
    wire host_ready,host_error,busy,done,safety_fault;
    wire [31:0] host_rdata;
    wire [3:0] halted_mask;
    integer i;
    reg [31:0] expected [0:15];

    always #5 clk=~clk;

    dream_gpu_host_v16 #(.WATCHDOG_LIMIT(1000)) dut(
      .clk(clk),.reset(reset),.host_valid(host_valid),.host_write(host_write),
      .host_addr(host_addr),.host_wdata(host_wdata),.host_ready(host_ready),
      .host_rdata(host_rdata),.host_error(host_error),.busy(busy),.done(done),
      .safety_fault(safety_fault),.halted_mask(halted_mask)
    );

    task write_reg(input [7:0] address,input [31:0] value);
      begin
        @(negedge clk); host_valid=1; host_write=1; host_addr=address; host_wdata=value;
        @(negedge clk); host_valid=0; host_write=0;
      end
    endtask

    task read_check(input [7:0] address,input [31:0] value);
      begin
        @(negedge clk); host_valid=1; host_write=0; host_addr=address; #1;
        if (!host_ready || host_error || host_rdata!==value)
          $fatal(1,"FAIL tensor read %h expected %h got %h",address,value,host_rdata);
        @(negedge clk); host_valid=0;
      end
    endtask

    initial begin
      repeat(4) @(negedge clk); reset=0;
      // A rows: [1,2,3,4], [5,6,7,8], [9,10,11,12], [13,14,15,16].
      write_reg(8'h90,32'h04030201);
      write_reg(8'h94,32'h08070605);
      write_reg(8'h98,32'h0C0B0A09);
      write_reg(8'h9C,32'h100F0E0D);
      // B rows: [1,2,0,0], [0,1,0,0], [0,0,1,0], [0,0,0,1].
      write_reg(8'hA0,32'h00000201);
      write_reg(8'hA4,32'h00000100);
      write_reg(8'hA8,32'h00000100);
      write_reg(8'hAC,32'h00000100);
      write_reg(8'h80,1);
      wait(dut.tensor_done); #1;
      read_check(8'h84,32'h1);
      expected[0]=1; expected[1]=4; expected[2]=3; expected[3]=4;
      expected[4]=5; expected[5]=16; expected[6]=7; expected[7]=8;
      expected[8]=9; expected[9]=28; expected[10]=11; expected[11]=12;
      expected[12]=13; expected[13]=40; expected[14]=15; expected[15]=16;
      for(i=0;i<16;i=i+1)
        read_check(8'hB0+i*4,expected[i]);

      // A soft reset also clears the tensor input/output banks.
      write_reg(8'h00,32'd2);
      write_reg(8'h90,32'h000003FE); // [-2, 3, 0, 0]
      write_reg(8'h94,32'h00000000);
      write_reg(8'h98,32'h00000000);
      write_reg(8'h9C,32'h00000000);
      write_reg(8'hA0,32'h00000004); // [4, 0, 0, 0]
      write_reg(8'hA4,32'h0000FB00); // [0, -5, 0, 0]
      write_reg(8'hA8,32'h00000000);
      write_reg(8'hAC,32'h00000000);
      write_reg(8'h80,32'd1);
      wait(dut.tensor_done); #1;
      read_check(8'hB0,32'hFFFFFFF8); // -8
      read_check(8'hB4,32'hFFFFFFF1); // -15
      read_check(8'hB8,32'd0);
      read_check(8'hBC,32'd0);
      $display("PASS: signed negative INT8 products and soft reset");
      $display("PASS: 4x4 INT8 matrix multiply outputs");
      $display("DREAM GPU v1.6 INT8 TENSOR TEST PASS");
      $finish;
    end

    initial begin
      #10000;
      $fatal(1,"tensor test timeout");
    end
endmodule
