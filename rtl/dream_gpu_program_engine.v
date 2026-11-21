`timescale 1ns/1ps

module dream_gpu_program_engine(
    input wire clk,
    input wire rst,

    input wire run,

    input wire program_we,
    input wire [7:0] program_addr,
    input wire [31:0] program_wdata,

    input wire host_we,
    input wire [1:0] host_lane,
    input wire [2:0] host_addr,
    input wire signed [15:0] host_wdata,

    input wire [1:0] debug_lane,
    input wire [2:0] debug_addr,
    output wire signed [15:0] debug_rdata,

    output reg [7:0] program_counter,
    output reg program_done,
    output wire busy
);

    localparam IDLE    = 2'd0;
    localparam FETCH   = 2'd1;
    localparam ISSUE   = 2'd2;
    localparam WAITING = 2'd3;

    localparam JUMP = 4'h8;
    localparam BEQZ = 4'h9;
    localparam HALT = 4'hF;

    reg [1:0] state;

    reg [31:0] instruction_memory [0:255];
    reg [31:0] instruction_reg;

    wire [31:0] fetched_instruction;
    wire [3:0] fetched_opcode;

    wire [2:0] fetched_ra;
    wire [7:0] fetched_target;

    wire signed [15:0] core_debug_rdata;
    wire signed [39:0] core_debug_acc;

    wire core_done;
    wire core_input_valid;

    wire [1:0] core_debug_lane;
    wire [2:0] core_debug_addr;

    wire [3:0] core_opcode;

    integer k;

    assign fetched_instruction = instruction_memory[program_counter];
    assign fetched_opcode = fetched_instruction[31:28];
    assign fetched_ra = fetched_instruction[24:22];
    assign fetched_target = fetched_instruction[7:0];

    assign busy = (state != IDLE);

    assign core_input_valid = (state == ISSUE);

    assign core_opcode = instruction_reg[31:28];

    // During BEQZ, use the core's register debug port
    // to inspect lane zero's selected register.
    assign core_debug_lane =
        (state == FETCH && fetched_opcode == BEQZ)
        ? 2'd0 : debug_lane;

    assign core_debug_addr =
        (state == FETCH && fetched_opcode == BEQZ)
        ? fetched_ra : debug_addr;

    assign debug_rdata = core_debug_rdata;

    // Instruction memory is writable by the host.
    always @(posedge clk) begin
        if (program_we)
            instruction_memory[program_addr] <= program_wdata;
    end

    dream_gpu_core_v04 core(
        .clk(clk),
        .rst(rst),

        .input_valid(core_input_valid),
        .opcode(core_opcode),
        .rd(instruction_reg[27:25]),
        .ra(instruction_reg[24:22]),
        .rb(instruction_reg[21:19]),
        .immediate(instruction_reg[15:0]),

        .host_we(host_we),
        .host_lane(host_lane),
        .host_addr(host_addr),
        .host_wdata(host_wdata),

        .debug_lane(core_debug_lane),
        .debug_addr(core_debug_addr),
        .debug_rdata(core_debug_rdata),

        .debug_acc_lane(2'd0),
        .debug_acc_addr(3'd0),
        .debug_acc(core_debug_acc),

        .done(core_done)
    );

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            program_counter <= 8'd0;
            instruction_reg <= 32'd0;
            program_done <= 1'b0;
        end else begin

            case (state)

                IDLE: begin
                    if (run) begin
                        program_counter <= 8'd0;
                        program_done <= 1'b0;
                        state <= FETCH;
                    end
                end

                FETCH: begin

                    case (fetched_opcode)

                        JUMP: begin
                            program_counter <= fetched_target;
                            state <= FETCH;
                        end

                        BEQZ: begin
                            if (core_debug_rdata == 16'sd0)
                                program_counter <= fetched_target;
                            else
                                program_counter <= program_counter + 1'b1;

                            state <= FETCH;
                        end

                        HALT: begin
                            program_done <= 1'b1;
                            state <= IDLE;
                        end

                        default: begin
                            instruction_reg <= fetched_instruction;
                            program_counter <= program_counter + 1'b1;
                            state <= ISSUE;
                        end

                    endcase
                end

                ISSUE: begin
                    state <= WAITING;
                end

                WAITING: begin
                    if (core_done)
                        state <= FETCH;
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule
