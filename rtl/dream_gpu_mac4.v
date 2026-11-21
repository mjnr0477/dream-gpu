module dream_gpu_mac4 (
    input clk, rst, enable, clear,
    input signed [15:0] a0,b0,a1,b1,a2,b2,a3,b3,
    output reg signed [39:0] acc0,acc1,acc2,acc3
);

always @(posedge clk) begin
    if (rst || clear) begin
        acc0 <= 0;
        acc1 <= 0;
        acc2 <= 0;
        acc3 <= 0;
    end else if (enable) begin
        acc0 <= acc0 + (a0 * b0);
        acc1 <= acc1 + (a1 * b1);
        acc2 <= acc2 + (a2 * b2);
        acc3 <= acc3 + (a3 * b3);
    end
end
endmodule
