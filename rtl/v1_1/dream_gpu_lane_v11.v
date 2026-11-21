`timescale 1ns/1ps

// One independent execution lane. Four instances run on the same clock edge.
module dream_gpu_lane_v11 #(
    parameter WATCHDOG_LIMIT = 100000,
    parameter LANE_ID = 0
)(
    input wire clk, reset, run_enable,
    input wire [31:0] instruction,
    input wire [31:0] mem_read_data,
    output reg mem_write,
    output reg [5:0] mem_address,
    output reg [31:0] mem_write_data,
    output reg [8:0] pc,
    output reg [31:0] accumulator,
    output reg halted,
    output reg safety_fault,
    output reg [3:0] fault_code,
    output reg [31:0] cycles,
    output reg [31:0] instructions,
    output reg [31:0] branches
);
    localparam OP_NOP=4'h0, OP_MOVI=4'h1, OP_ADDI=4'h2,
      OP_SUBI=4'h3, OP_XORI=4'h4, OP_BRZ=4'h5, OP_JMP=4'h6,
      OP_HALT=4'h7, OP_LID=4'h8, OP_LD=4'h9, OP_ST=4'hA,
      OP_MACI=4'hB;

    wire signed [31:0] mac_a = $signed({{16{mem_read_data[15]}},mem_read_data[15:0]});
    wire signed [31:0] mac_b = $signed({{16{instruction[21]}},instruction[21:6]});
    wire signed [31:0] mac_product = mac_a * mac_b;
    reg [31:0] next_pc;
    reg [31:0] watchdog;

    always @* begin
      mem_address = instruction[5:0];
      mem_write_data = accumulator;
      mem_write = run_enable && !halted && !safety_fault &&
                  (pc < 256) && (instruction[31:28] == OP_ST);
    end

    always @(posedge clk or posedge reset) begin
      if (reset) begin
        pc<=0; accumulator<=0; halted<=0; safety_fault<=0; fault_code<=0;
        cycles<=0; instructions<=0; branches<=0; watchdog<=0;
      end else if (run_enable && !halted && !safety_fault) begin
        cycles<=cycles+1;
        watchdog<=watchdog+1;
        if (watchdog >= WATCHDOG_LIMIT) begin
          safety_fault<=1; fault_code<=4'd1;
        end else if (pc >= 256) begin
          safety_fault<=1; fault_code<=4'd2;
        end else begin
          instructions<=instructions+1;
          next_pc = pc + 1;
          case (instruction[31:28])
            OP_NOP: pc<=next_pc[8:0];
            OP_MOVI: begin accumulator<={{16{instruction[15]}},instruction[15:0]}; pc<=next_pc[8:0]; end
            OP_ADDI: begin accumulator<=accumulator+{{16{instruction[15]}},instruction[15:0]}; pc<=next_pc[8:0]; end
            OP_SUBI: begin accumulator<=accumulator-{{16{instruction[15]}},instruction[15:0]}; pc<=next_pc[8:0]; end
            OP_XORI: begin accumulator<=accumulator^{{16{instruction[15]}},instruction[15:0]}; pc<=next_pc[8:0]; end
            OP_LID: begin accumulator<=LANE_ID; pc<=next_pc[8:0]; end
            OP_LD: begin accumulator<=mem_read_data; pc<=next_pc[8:0]; end
            OP_ST: pc<=next_pc[8:0];
            OP_MACI: begin accumulator<=accumulator+mac_product; pc<=next_pc[8:0]; end
            OP_BRZ: begin
              if (accumulator==0) begin
                next_pc = pc + 1 + {{16{instruction[15]}},instruction[15:0]};
                if (next_pc>=256) begin safety_fault<=1; fault_code<=4'd3; end
                else begin pc<=next_pc[8:0]; branches<=branches+1; end
              end else pc<=next_pc[8:0];
            end
            OP_JMP: begin
              next_pc=instruction[8:0];
              if (next_pc>=256) begin safety_fault<=1; fault_code<=4'd3; end
              else begin pc<=next_pc[8:0]; branches<=branches+1; end
            end
            OP_HALT: begin halted<=1; pc<=next_pc[8:0]; end
            default: begin safety_fault<=1; fault_code<=4'd4; end
          endcase
        end
      end
    end
endmodule
