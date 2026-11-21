`timescale 1ns/1ps
module tb_dream_gpu_v11_parallel;
  reg clk=0, reset=1, run_enable=0, imem_write=0;
  reg [7:0] imem_address=0;
  reg [31:0] imem_data=0;
  wire [3:0] lane_mask, halted_mask;
  wire [35:0] pc_bus;
  wire [127:0] accum_bus;
  wire safety_fault, done;
  wire [3:0] fault_code;
  wire [31:0] cycle_count,instruction_count,branch_count;
  integer errors=0;
  always #5 clk=~clk;

  dream_gpu_engine_v11 #(.WATCHDOG_LIMIT(1000)) dut(
    .clk(clk),.reset(reset),.run_enable(run_enable),
    .imem_write(imem_write),.imem_address(imem_address),.imem_data(imem_data),
    .lane_mask(lane_mask),.pc_bus(pc_bus),.accum_bus(accum_bus),
    .halted_mask(halted_mask),.safety_fault(safety_fault),.fault_code(fault_code),
    .done(done),.cycle_count(cycle_count),.instruction_count(instruction_count),
    .branch_count(branch_count)
  );

  task load(input [7:0] a,input [31:0] d);
    begin
      @(negedge clk); imem_write=1; imem_address=a; imem_data=d;
      @(negedge clk); imem_write=0;
    end
  endtask

  task clear_and_reset;
    begin
      run_enable=0; reset=1; repeat(3) @(negedge clk); reset=0;
    end
  endtask

  initial begin
    $display("DREAM GPU v1.1 FOUR-LANE PARALLEL VERIFICATION");
    repeat(3) @(negedge clk); reset=0;
    // Every lane independently executes LID, ADDI 10, HALT.
    load(0,32'h80000000);
    load(1,32'h2000000A);
    load(2,32'h70000000);
    run_enable=1;
    @(negedge clk);
    if(pc_bus[8:0]!==9'd1 || pc_bus[17:9]!==9'd1 ||
       pc_bus[26:18]!==9'd1 || pc_bus[35:27]!==9'd1)
      $fatal(1,"FAIL: all four PCs did not advance on the same edge");
    if(accum_bus[31:0]!==0 || accum_bus[63:32]!==1 ||
       accum_bus[95:64]!==2 || accum_bus[127:96]!==3)
      $fatal(1,"FAIL: lane IDs not executed in parallel");
    $display("PASS: all four lanes issued LID on one clock edge");
    wait(done); #1;
    if(safety_fault) $fatal(1,"FAIL: unexpected parallel execution fault");
    if(accum_bus[31:0]!==32'd10 || accum_bus[63:32]!==32'd11 ||
       accum_bus[95:64]!==32'd12 || accum_bus[127:96]!==32'd13)
      $fatal(1,"FAIL: parallel accumulators incorrect");
    if(cycle_count!==32'd3 || instruction_count!==32'd12)
      $fatal(1,"FAIL: expected 3 clocks / 12 total lane instructions");
    $display("PASS: four independent lanes completed in 3 clocks (12 lane instructions)");

    // Verify lane-private memory and MACI in the parallel engine.
    clear_and_reset;
    load(0,32'h80000000); // LID
    load(1,32'h20000002); // ADDI 2
    load(2,32'hA0000004); // ST [4], each lane's own bank
    load(3,32'h10000000); // MOVI 0
    load(4,32'hB00000C4); // MACI +3, [4]
    load(5,32'h70000000); // HALT
    run_enable=1;
    wait(done); #1;
    if(safety_fault) $fatal(1,"FAIL: parallel private-memory MACI fault");
    if(accum_bus[31:0]!==32'd6 || accum_bus[63:32]!==32'd9 ||
       accum_bus[95:64]!==32'd12 || accum_bus[127:96]!==32'd15)
      $fatal(1,"FAIL: parallel private-memory MACI values incorrect");
    if(cycle_count!==32'd6 || instruction_count!==32'd24)
      $fatal(1,"FAIL: parallel MACI cycle/instruction counts incorrect");
    $display("PASS: all lanes used private memory and MACI simultaneously");
    $display("DREAM GPU v1.1 FOUR-LANE PARALLEL TEST PASS");
    $finish;
  end
endmodule
