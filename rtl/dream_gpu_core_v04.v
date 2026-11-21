module dream_gpu_core_v04(
    input clk,
    input rst,

    input input_valid,
    input [3:0] opcode,
    input [2:0] rd,
    input [2:0] ra,
    input [2:0] rb,
    input signed [15:0] immediate,

    input host_we,
    input [1:0] host_lane,
    input [2:0] host_addr,
    input signed [15:0] host_wdata,

    input [1:0] debug_lane,
    input [2:0] debug_addr,
    output signed [15:0] debug_rdata,

    input [1:0] debug_acc_lane,
    input [2:0] debug_acc_addr,
    output signed [39:0] debug_acc,

    output reg done
);

localparam NOP  = 4'h0;
localparam ADD  = 4'h1;
localparam SUB  = 4'h2;
localparam MUL  = 4'h3;
localparam MAC  = 4'h4;
localparam MOVI = 4'h5;
localparam LOAD = 4'h6;
localparam STORE = 4'h7;

reg signed [15:0] regs [0:3][0:7];
reg signed [39:0] accum [0:3][0:7];

wire signed [31:0] product [0:3];

wire decoded_valid;
wire execute;

wire [31:0] memory_addr;
wire [63:0] memory_wdata;
wire [63:0] memory_rdata;
wire [3:0] memory_we;

integer i;
integer j;
genvar g;

dream_gpu_decoder_v04 decoder(
    .opcode(opcode),
    .decoded_valid(decoded_valid)
);

dream_gpu_controller controller(
    .issue(input_valid),
    .decoded_valid(decoded_valid),
    .execute(execute)
);

generate
    for (g=0; g<4; g=g+1) begin: LANE_CONNECTIONS

        assign product[g] =
            $signed(regs[g][ra]) *
            $signed(regs[g][rb]);

        assign memory_addr[g*8 +: 8] =
            regs[g][ra][7:0];

        assign memory_wdata[g*16 +: 16] =
            regs[g][rb];

    end
endgenerate

assign memory_we =
    (execute && opcode == STORE) ? 4'b1111 : 4'b0000;

dream_gpu_memory memory_unit(
    .clk(clk),
    .we(memory_we),
    .addr(memory_addr),
    .wdata(memory_wdata),
    .rdata(memory_rdata)
);

assign debug_rdata = regs[debug_lane][debug_addr];
assign debug_acc = accum[debug_acc_lane][debug_acc_addr];

always @(posedge clk) begin
    if (rst) begin
        done <= 1'b0;

        for (i=0; i<4; i=i+1) begin
            for (j=0; j<8; j=j+1) begin
                regs[i][j] <= 16'sd0;
                accum[i][j] <= 40'sd0;
            end
        end

    end else begin
        done <= 1'b0;

        if (host_we) begin
            regs[host_lane][host_addr] <= host_wdata;
        end

        else if (execute) begin
            done <= 1'b1;

            case (opcode)

                NOP: begin
                end

                ADD: begin
                    for (i=0; i<4; i=i+1)
                        regs[i][rd] <= regs[i][ra] + regs[i][rb];
                end

                SUB: begin
                    for (i=0; i<4; i=i+1)
                        regs[i][rd] <= regs[i][ra] - regs[i][rb];
                end

                MUL: begin
                    for (i=0; i<4; i=i+1)
                        regs[i][rd] <= product[i][15:0];
                end

                MAC: begin
                    for (i=0; i<4; i=i+1)
                        accum[i][rd] <= accum[i][rd]
                            + {{8{product[i][31]}}, product[i]};
                end

                MOVI: begin
                    for (i=0; i<4; i=i+1)
                        regs[i][rd] <= immediate;
                end

                LOAD: begin
                    for (i=0; i<4; i=i+1)
                        regs[i][rd] <=
                            memory_rdata[i*16 +: 16];
                end

                STORE: begin
                    // Memory writes occur in dream_gpu_memory
                    // on this same rising clock edge.
                end

                default: begin
                    done <= 1'b0;
                end

            endcase
        end
    end
end

endmodule
