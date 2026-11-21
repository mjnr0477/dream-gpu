module dream_gpu_decoder(
    input [3:0] opcode,
    output reg decoded_valid
);

always @(*) begin
    decoded_valid = 1'b1;

    case(opcode)
        4'h0: decoded_valid = 1'b1; // NOP
        4'h1: decoded_valid = 1'b1; // ADD
        4'h2: decoded_valid = 1'b1; // SUB
        4'h3: decoded_valid = 1'b1; // MUL
        4'h4: decoded_valid = 1'b1; // MAC
        4'h5: decoded_valid = 1'b1; // MOVI
        default: decoded_valid = 1'b0;
    endcase
end

endmodule
