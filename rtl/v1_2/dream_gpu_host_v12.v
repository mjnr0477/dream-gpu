`timescale 1ns/1ps

// Simple synchronous memory-mapped host interface for the DREAM GPU v1.2 RTL.
// A host transaction is accepted on a rising edge when host_valid is high.
module dream_gpu_host_v12 #(
    parameter WATCHDOG_LIMIT=100000
)(
    input wire clk, reset,
    input wire host_valid, host_write,
    input wire [7:0] host_addr,
    input wire [31:0] host_wdata,
    output wire host_ready,
    output reg [31:0] host_rdata,
    output wire host_error,
    output wire busy, done, safety_fault,
    output wire [3:0] halted_mask
);
    reg run_enable;
    reg [7:0] imem_address_reg;
    reg [31:0] imem_data_reg;
    reg [7:0] dmem_address_reg;
    reg [31:0] dmem_data_reg;
    wire imem_write = host_valid && host_write && host_addr==8'h28;
    wire dmem_write = host_valid && host_write && host_addr==8'h38;
    wire [3:0] lane_mask;
    wire [35:0] pc_bus;
    wire [127:0] accum_bus;
    wire [3:0] fault_code;
    wire [31:0] cycle_count,instruction_count,branch_count;
    wire [31:0] dmem_read_data;
    wire [1:0] dmem_lane=dmem_address_reg[7:6];
    wire [5:0] dmem_offset=dmem_address_reg[5:0];

    assign host_ready=host_valid;
    assign host_error=1'b0;
    assign busy=run_enable && !done && !safety_fault;

    dream_gpu_engine_v12 #(.WATCHDOG_LIMIT(WATCHDOG_LIMIT)) engine(
      .clk(clk),.reset(reset),.run_enable(run_enable),
      .imem_write(imem_write),.imem_address(imem_address_reg),
      .imem_data(imem_data_reg),
      .host_dmem_we(dmem_write),.host_dmem_lane(dmem_lane),
      .host_dmem_address(dmem_offset),.host_dmem_wdata(dmem_data_reg),
      .host_dmem_rdata(dmem_read_data),
      .lane_mask(lane_mask),.pc_bus(pc_bus),.accum_bus(accum_bus),
      .halted_mask(halted_mask),.safety_fault(safety_fault),
      .fault_code(fault_code),.done(done),.cycle_count(cycle_count),
      .instruction_count(instruction_count),.branch_count(branch_count)
    );

    always @(posedge clk or posedge reset) begin
      if(reset) begin
        run_enable<=0;
        imem_address_reg<=0;
        imem_data_reg<=0;
        dmem_address_reg<=0;
        dmem_data_reg<=0;
      end else if(host_valid && host_write) begin
        case(host_addr)
          8'h00: run_enable<=host_wdata[0];
          8'h20: imem_address_reg<=host_wdata[7:0];
          8'h24: imem_data_reg<=host_wdata;
          8'h30: dmem_address_reg<=host_wdata[7:0];
          8'h34: dmem_data_reg<=host_wdata;
          default: begin end
        endcase
      end
    end

    always @* begin
      host_rdata=0;
      case(host_addr)
        8'h00: host_rdata={31'b0,run_enable};
        8'h04: host_rdata={24'b0,safety_fault,done,halted_mask,2'b0};
        8'h08: host_rdata={28'b0,fault_code};
        8'h0C: host_rdata=cycle_count;
        8'h10: host_rdata=instruction_count;
        8'h14: host_rdata=branch_count;
        8'h20: host_rdata={24'b0,imem_address_reg};
        8'h24: host_rdata=imem_data_reg;
        8'h30: host_rdata={24'b0,dmem_address_reg};
        8'h34: host_rdata=dmem_data_reg;
        8'h3C: host_rdata=dmem_read_data;
        8'h40: host_rdata=accum_bus[31:0];
        8'h44: host_rdata=accum_bus[63:32];
        8'h48: host_rdata=accum_bus[95:64];
        8'h4C: host_rdata=accum_bus[127:96];
        8'h50: host_rdata={23'b0,pc_bus[8:0]};
        8'h54: host_rdata={23'b0,pc_bus[17:9]};
        8'h58: host_rdata={23'b0,pc_bus[26:18]};
        8'h5C: host_rdata={23'b0,pc_bus[35:27]};
        default: host_rdata=0;
      endcase
    end
endmodule
