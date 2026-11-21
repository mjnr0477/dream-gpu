`timescale 1ns/1ps

module dream_gpu_engine_v08 #(
    parameter WATCHDOG_LIMIT = 100000
)(
    input wire clk,
    input wire reset,
    input wire run_enable,

    input wire imem_write,
    input wire [7:0] imem_address,
    input wire [31:0] imem_data,

    output wire [3:0] lane_mask,
    output wire [35:0] pc_bus,
    output wire [127:0] accum_bus,

    output wire safety_fault,
    output wire done,
    output wire [31:0] cycle_count,
    output wire [31:0] instruction_count,
    output wire [31:0] branch_count,
    output wire [1:0] selected_lane
);

    reg [31:0] instruction_memory [0:255];
    reg [31:0] data_memory [0:255];

    reg [1:0] round_robin;
    reg [1:0] selected;
    reg found;

    wire [31:0] current_instruction;
    wire [31:0] mem_read_data;
    wire mem_write;
    wire [7:0] mem_address;
    wire [31:0] mem_write_data;
    wire core_step;

    integer i;
    integer scan;

    always @* begin
        selected = round_robin;
        found = 0;

        for (scan = 0; scan < 4; scan = scan + 1) begin
            if (!found && lane_mask[(round_robin + scan) % 4]) begin
                selected = (round_robin + scan) % 4;
                found = 1;
            end
        end
    end

    assign selected_lane = selected;

    assign current_instruction =
        instruction_memory[pc_bus[selected*9 +: 9]];

    assign mem_read_data = data_memory[mem_address];

    assign core_step = run_enable && found && !done && !safety_fault;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            round_robin <= 0;

            for (i = 0; i < 256; i = i + 1) begin
                instruction_memory[i] <= 32'h00000000;
                data_memory[i] <= 32'h00000000;
            end
        end
        else begin
            if (imem_write)
                instruction_memory[imem_address] <= imem_data;

            if (mem_write)
                data_memory[mem_address] <= mem_write_data;

            if (core_step)
                round_robin <= selected + 1'b1;
        end
    end

    dream_gpu_core_v08 #(
        .WATCHDOG_LIMIT(WATCHDOG_LIMIT)
    ) processor (
        .clk(clk),
        .reset(reset),
        .step(core_step),
        .lane_id(selected),
        .instruction(current_instruction),
        .mem_read_data(mem_read_data),

        .mem_write(mem_write),
        .mem_address(mem_address),
        .mem_write_data(mem_write_data),

        .lane_mask(lane_mask),
        .pc_bus(pc_bus),
        .accum_bus(accum_bus),

        .safety_fault(safety_fault),
        .cycle_count(cycle_count),
        .instruction_count(instruction_count),
        .branch_count(branch_count),
        .done(done)
    );

endmodule
