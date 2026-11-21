`timescale 1ns/1ps

module dream_gpu_core_v09 #(
    parameter WATCHDOG_LIMIT = 100000
)(
    input wire clk,
    input wire reset,
    input wire step,
    input wire [1:0] lane_id,
    input wire [31:0] instruction,
    input wire [31:0] mem_read_data,

    output reg mem_write,
    output reg [7:0] mem_address,
    output reg [31:0] mem_write_data,

    output reg [3:0] lane_mask,
    output reg [35:0] pc_bus,
    output reg [127:0] accum_bus,

    output reg safety_fault,
    output reg [3:0] fault_code,
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
    localparam OP_LID  = 4'h8;
    localparam OP_LD   = 4'h9;
    localparam OP_ST   = 4'hA;

    reg [8:0] pc [0:3];
    reg [31:0] accum [0:3];
    reg halted [0:3];

    reg [31:0] watchdog;
    reg [31:0] next_pc;

    integer i;
    integer j;

    wire all_halted =
        halted[0] && halted[1] &&
        halted[2] && halted[3];

    assign done = all_halted;

    always @* begin
        for (j = 0; j < 4; j = j + 1) begin
            lane_mask[j] = !halted[j];
            pc_bus[j*9 +: 9] = pc[j];
            accum_bus[j*32 +: 32] = accum[j];
        end

        mem_address = {lane_id, instruction[5:0]};
        mem_write_data = accum[lane_id];

        mem_write =
            step &&
            !halted[lane_id] &&
            !safety_fault &&
            (pc[lane_id] < 256) &&
            (instruction[31:28] == OP_ST);
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            watchdog <= 0;
            cycle_count <= 0;
            instruction_count <= 0;
            branch_count <= 0;
            safety_fault <= 0;
            fault_code <= 0;

            for (i = 0; i < 4; i = i + 1) begin
                pc[i] <= 0;
                accum[i] <= 0;
                halted[i] <= 0;
            end
        end
        else if (step && !all_halted && !safety_fault) begin
            cycle_count <= cycle_count + 1;
            watchdog <= watchdog + 1;

            if (watchdog >= WATCHDOG_LIMIT) begin
                safety_fault <= 1;
                fault_code <= 4'd1;
            end
            else if (halted[lane_id] || pc[lane_id] >= 256) begin
                safety_fault <= 1;
                fault_code <= 4'd2;
            end
            else begin
                instruction_count <= instruction_count + 1;
                next_pc = pc[lane_id] + 1;

                case (instruction[31:28])
                    OP_NOP: begin
                        pc[lane_id] <= next_pc[8:0];
                    end

                    OP_MOVI: begin
                        accum[lane_id] <=
                            {{16{instruction[15]}}, instruction[15:0]};
                        pc[lane_id] <= next_pc[8:0];
                    end

                    OP_ADDI: begin
                        accum[lane_id] <= accum[lane_id] +
                            {{16{instruction[15]}}, instruction[15:0]};
                        pc[lane_id] <= next_pc[8:0];
                    end

                    OP_SUBI: begin
                        accum[lane_id] <= accum[lane_id] -
                            {{16{instruction[15]}}, instruction[15:0]};
                        pc[lane_id] <= next_pc[8:0];
                    end

                    OP_XORI: begin
                        accum[lane_id] <= accum[lane_id] ^
                            {{16{instruction[15]}}, instruction[15:0]};
                        pc[lane_id] <= next_pc[8:0];
                    end

                    OP_LID: begin
                        accum[lane_id] <= lane_id;
                        pc[lane_id] <= next_pc[8:0];
                    end

                    OP_LD: begin
                        accum[lane_id] <= mem_read_data;
                        pc[lane_id] <= next_pc[8:0];
                    end

                    OP_ST: begin
                        pc[lane_id] <= next_pc[8:0];
                    end

                    OP_BRZ: begin
                        if (accum[lane_id] == 0) begin
                            next_pc = pc[lane_id] + 1 +
                                {{16{instruction[15]}}, instruction[15:0]};

                            if (next_pc >= 256) begin
                                safety_fault <= 1;
                                fault_code <= 4'd3;
                            end
                            else begin
                                pc[lane_id] <= next_pc[8:0];
                                branch_count <= branch_count + 1;
                            end
                        end
                        else begin
                            pc[lane_id] <= next_pc[8:0];
                        end
                    end

                    OP_JMP: begin
                        next_pc = instruction[8:0];

                        if (next_pc >= 256) begin
                            safety_fault <= 1;
                            fault_code <= 4'd3;
                        end
                        else begin
                            pc[lane_id] <= next_pc[8:0];
                            branch_count <= branch_count + 1;
                        end
                    end

                    OP_HALT: begin
                        halted[lane_id] <= 1;
                        pc[lane_id] <= next_pc[8:0];
                    end

                    default: begin
                        safety_fault <= 1;
                        fault_code <= 4'd4;
                    end
                endcase
            end
        end
    end

endmodule
