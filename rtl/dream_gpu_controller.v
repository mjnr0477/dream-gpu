module dream_gpu_controller(
    input issue,
    input decoded_valid,
    output execute
);

assign execute = issue & decoded_valid;

endmodule
