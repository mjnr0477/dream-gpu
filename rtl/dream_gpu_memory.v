`timescale 1ns/1ps

module dream_gpu_memory #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 16,
    parameter DEPTH = 256
)(
    input wire clk,
    input wire [3:0] we,
    input wire [31:0] addr,
    input wire [63:0] wdata,
    output wire [63:0] rdata
);

    genvar lane;

    generate
        for (lane = 0; lane < 4; lane = lane + 1) begin : MEMORY_LANE

            reg [DATA_WIDTH-1:0] bank [0:DEPTH-1];

            wire [ADDR_WIDTH-1:0] lane_addr;
            wire [DATA_WIDTH-1:0] lane_wdata;

            assign lane_addr =
                addr[lane*ADDR_WIDTH +: ADDR_WIDTH];

            assign lane_wdata =
                wdata[lane*DATA_WIDTH +: DATA_WIDTH];

            assign rdata[lane*DATA_WIDTH +: DATA_WIDTH] =
                bank[lane_addr];

            always @(posedge clk) begin
                if (we[lane]) begin
                    bank[lane_addr] <= lane_wdata;
                end
            end

        end
    endgenerate

endmodule
