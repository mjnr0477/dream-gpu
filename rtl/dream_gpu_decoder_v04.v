module dream_gpu_decoder_v04(
    input wire [3:0] opcode,
    output reg decoded_valid
);

always @(*) begin
    case (opcode)
        4'h0, 4'h1, 4'h2, 4'h3,
        4'h4, 4'h5, 4'h6, 4'h7:
            decoded_valid = 1'b1;
        default:
            decoded_valid = 1'b0;
    endcase
end

endmodule
