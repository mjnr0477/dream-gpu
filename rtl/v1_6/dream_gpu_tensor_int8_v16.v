`timescale 1ns/1ps

// Resource-conscious 4x4 signed INT8 matrix multiply.
// Only one output row is active at a time: 16 signed 8x8 multipliers compute
// four dot products in parallel, and four output rows are committed over
// four compute clocks. Each matrix row is packed with column 0 in byte 0.
module dream_gpu_tensor_int8_v16(
    input wire clk,
    input wire reset,
    input wire start,
    input wire write_a,
    input wire write_b,
    input wire [1:0] row_address,
    input wire [31:0] write_data,
    input wire [3:0] result_address,
    output wire [31:0] result_data,
    output reg busy,
    output reg done
);
    reg [31:0] matrix_a [0:3];
    reg [31:0] matrix_b [0:3];
    reg [31:0] matrix_c [0:15];
    reg [1:0] active_row;

    wire signed [15:0] product [0:15];
    wire signed [31:0] dot [0:3];
    genvar c,k;
    generate
      for (c=0;c<4;c=c+1) begin: COL
        for (k=0;k<4;k=k+1) begin: MUL
          assign product[c*4+k] =
            $signed(matrix_a[active_row][k*8 +: 8]) *
            $signed(matrix_b[k][c*8 +: 8]);
        end
        assign dot[c] =
            {{16{product[c*4+0][15]}},product[c*4+0]} +
            {{16{product[c*4+1][15]}},product[c*4+1]} +
            {{16{product[c*4+2][15]}},product[c*4+2]} +
            {{16{product[c*4+3][15]}},product[c*4+3]};
      end
    endgenerate

    assign result_data = matrix_c[result_address];

    integer i;
    always @(posedge clk or posedge reset) begin
      if (reset) begin
        for (i=0;i<4;i=i+1) begin
          matrix_a[i] <= 0;
          matrix_b[i] <= 0;
        end
        for (i=0;i<16;i=i+1)
          matrix_c[i] <= 0;
        active_row <= 0;
        busy <= 0;
        done <= 0;
      end else begin
        if (write_a)
          matrix_a[row_address] <= write_data;
        if (write_b)
          matrix_b[row_address] <= write_data;

        if (start && !busy) begin
          busy <= 1;
          done <= 0;
          active_row <= 0;
        end else if (busy) begin
          matrix_c[active_row*4+0] <= dot[0];
          matrix_c[active_row*4+1] <= dot[1];
          matrix_c[active_row*4+2] <= dot[2];
          matrix_c[active_row*4+3] <= dot[3];
          if (active_row==3) begin
            busy <= 0;
            done <= 1;
          end else begin
            active_row <= active_row+1'b1;
          end
        end
      end
    end
endmodule
