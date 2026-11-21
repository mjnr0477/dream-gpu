`timescale 1ns/1ps

module dream_gpu_core_v06 #(
    parameter WATCHDOG_LIMIT = 100000
)(
    input wire clk,
    input wire reset,
    input wire step,
    input wire [1:0] lane_id,
    input wire [31:0] instruction,

    output reg [3:0] lane_mask,
    output reg [35:0] pc_bus,
    output reg [127:0] accum_bus,

    output reg safety_fault,
    output reg [31:0] cycle_count,
    output reg [31:0] instruction_count,
    output reg [31:0] branch_count,
    output wire done
);

    localparam OP_NOP  = 4'h0;
    localparam OP_MOVI = 4'h1;
    localparam OP_ADDI = 4'h2;
    localparam OP_SUBI = 4'h3;
    localparam OP_XORI = 4'h4;
    localparam OP_BRZ  = 4'h5;
    localparam OP_JMP  = 4'h6;
    localparam OP_HALT = 4'h7;

    reg [8:0] pc [0:3];
    reg [31:0] accum [0:3];
    reg halted [0:3];

    reg [31:0] watchdog;
    reg [31:0] next_pc;

    integer i;

    wire all_halted = halted[0] && halted[1] &&
                      halted[2] && halted[3];

    assign done = all_halted;

    always @* begin
        for (integer j = 0; j < 4; j = j + 1) begin
            lane_mask[j] = !halted[j];
            pc_bus[j*9 +: 9] = pc[j];
            accum_bus[j*32 +: 32] = accum[j];
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            watchdog <= 0;
            cycle_count <= 0;
            instruction_count <= 0;
            branch_count <= 0;
            safety_fault <= 0;

            for (i = 0; i < 4; i = i + 1) begin
                pc[i] <= 0;
                accum[i] <= 0;
                halted[i] <= 0;
            end
        end
        else if (step && !all_halted && !safety_fault) begin

            watchdog <= watchdog + 1;
            cycle_count <= cycle_count + 1;

            if (watchdog >= WATCHDOG_LIMIT) begin
                safety_fault <= 1;
            end
            else if (halted[lane_id]) begin
                safety_fault <= 1;
            end
            else if (pc[lane_id] >= 256) begin
                safety_fault <= 1;
            end
            else begin

                instruction_count <= instruction_count + 1;
                next_pc = pc[lane_id] + 1;

                case (instruction[31:28])

                    OP_NOP: begin
                        pc[lane_id] <= next_pc;
                    end

                    OP_MOVI: begin
                        accum[lane_id] <=
                            {{16{instruction[15]}},
                             instruction[15:0]};
                        pc[lane_id] <= next_pc;
                    end

                    OP_ADDI: begin
                        accum[lane_id] <= accum[lane_id] +
                            {{16{instruction[15]}},
                             instruction[15:0]};
                        pc[lane_id] <= next_pc;
                    end

                    OP_SUBI: begin
                        accum[lane_id] <= accum[lane_id] -
                            {{16{instruction[15]}},
                             instruction[15:0]};
                        pc[lane_id] <= next_pc;
                    end

                    OP_XORI: begin
                        accum[lane_id] <= accum[lane_id] ^
                            {{16{instruction[15]}},
                             instruction[15:0]};
                        pc[lane_id] <= next_pc;
                    end

                    OP_BRZ: begin
                        if (accum[lane_id] == 0) begin
                            next_pc = pc[lane_id] + 1 +
                                {{17{instruction[15]}},
                                 instruction[15:0]};
                            pc[lane_id] <= next_pc[8:0];
                            branch_count <= branch_count + 1;
                        end
                        else begin
                            pc[lane_id] <= next_pc;
                        end
                    end

                    OP_JMP: begin
                        pc[lane_id] <= instruction[8:0];
                        branch_count <= branch_count + 1;
                    end

                    OP_HALT: begin
                        halted[lane_id] <= 1;
                        pc[lane_id] <= next_pc;
                    end

                    default: begin
                        safety_fault <= 1;
                    end

                endcase
            end
        end
    end

endmodule
