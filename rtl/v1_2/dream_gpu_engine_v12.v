`timescale 1ns/1ps

// Four independent lanes issue one instruction each on every enabled clock.
module dream_gpu_engine_v11 #(
    parameter WATCHDOG_LIMIT=100000
)(
    input wire clk, reset, run_enable,
    input wire imem_write,
    input wire [7:0] imem_address,
    input wire [31:0] imem_data,
    input wire host_dmem_we,
    input wire [1:0] host_dmem_lane,
    input wire [5:0] host_dmem_address,
    input wire [31:0] host_dmem_wdata,
    output wire [31:0] host_dmem_rdata,
    output wire [3:0] lane_mask,
    output wire [35:0] pc_bus,
    output wire [127:0] accum_bus,
    output wire [3:0] halted_mask,
    output wire safety_fault,
    output wire [3:0] fault_code,
    output wire done,
    output wire [31:0] cycle_count,
    output wire [31:0] instruction_count,
    output wire [31:0] branch_count
);
    reg [31:0] instruction_memory[0:255];
    reg [31:0] private_memory[0:3][0:63];

    wire [31:0] lane_instruction[0:3];
    wire [31:0] lane_mem_read[0:3];
    wire [3:0] lane_mem_write;
    wire [5:0] lane_mem_address[0:3];
    wire [31:0] lane_mem_write_data[0:3];
    wire [31:0] lane_cycles[0:3];
    wire [31:0] lane_instructions[0:3];
    wire [31:0] lane_branches[0:3];
    wire [3:0] lane_fault;
    wire [15:0] lane_fault_codes;
    wire [8:0] lane_pc[0:3];
    wire [31:0] lane_accum[0:3];
    integer i,j;

    genvar g;
    generate for(g=0;g<4;g=g+1) begin: LANES
      assign lane_instruction[g] = (lane_pc[g] < 256) ? instruction_memory[lane_pc[g]] : 32'h00000000;
      assign lane_mem_read[g] = private_memory[g][lane_mem_address[g]];
      dream_gpu_lane_v11 #(.WATCHDOG_LIMIT(WATCHDOG_LIMIT),.LANE_ID(g)) lane (
        .clk(clk),.reset(reset),.run_enable(run_enable),
        .instruction(lane_instruction[g]),.mem_read_data(lane_mem_read[g]),
        .mem_write(lane_mem_write[g]),.mem_address(lane_mem_address[g]),
        .mem_write_data(lane_mem_write_data[g]),.pc(lane_pc[g]),
        .accumulator(lane_accum[g]),.halted(halted_mask[g]),
        .safety_fault(lane_fault[g]),.fault_code(lane_fault_codes[g*4 +: 4]),
        .cycles(lane_cycles[g]),.instructions(lane_instructions[g]),
        .branches(lane_branches[g])
      );
      assign lane_mask[g] = !halted_mask[g];
      assign pc_bus[g*9 +: 9] = lane_pc[g];
      assign accum_bus[g*32 +: 32] = lane_accum[g];
    end endgenerate

    always @(posedge clk or posedge reset) begin
      if(reset) begin
        for(i=0;i<256;i=i+1) instruction_memory[i]<=0;
        for(i=0;i<4;i=i+1)
          for(j=0;j<64;j=j+1) private_memory[i][j]<=0;
      end else begin
        if(imem_write) instruction_memory[imem_address]<=imem_data;
        for(i=0;i<4;i=i+1)
          if(lane_mem_write[i] && !(host_dmem_we && host_dmem_lane == i))
            private_memory[i][lane_mem_address[i]]<=lane_mem_write_data[i];
        if(host_dmem_we)
          private_memory[host_dmem_lane][host_dmem_address]<=host_dmem_wdata;
      end
    end

    assign host_dmem_rdata = private_memory[host_dmem_lane][host_dmem_address];
    assign done = &halted_mask;
    assign safety_fault = |lane_fault;
    assign fault_code = lane_fault[0] ? lane_fault_codes[3:0] :
                        lane_fault[1] ? lane_fault_codes[7:4] :
                        lane_fault[2] ? lane_fault_codes[11:8] :
                        lane_fault_codes[15:12];
    assign cycle_count = (lane_cycles[0] > lane_cycles[1]) ?
       ((lane_cycles[0] > lane_cycles[2]) ?
         ((lane_cycles[0] > lane_cycles[3]) ? lane_cycles[0] : lane_cycles[3]) :
         ((lane_cycles[2] > lane_cycles[3]) ? lane_cycles[2] : lane_cycles[3])) :
       ((lane_cycles[1] > lane_cycles[2]) ?
         ((lane_cycles[1] > lane_cycles[3]) ? lane_cycles[1] : lane_cycles[3]) :
         ((lane_cycles[2] > lane_cycles[3]) ? lane_cycles[2] : lane_cycles[3]));
    assign instruction_count=lane_instructions[0]+lane_instructions[1]+lane_instructions[2]+lane_instructions[3];
    assign branch_count=lane_branches[0]+lane_branches[1]+lane_branches[2]+lane_branches[3];
endmodule
