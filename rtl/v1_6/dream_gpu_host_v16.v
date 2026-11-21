`timescale 1ns/1ps

// v1.6 host-bus extension: preserves the v1.2 register map and adds
// a small 4x4 signed INT8 matrix multiply register bank.
module dream_gpu_host_v16 #(
    parameter WATCHDOG_LIMIT=100000
)(
    input wire clk, reset,
    input wire host_valid, host_write,
    input wire [7:0] host_addr,
    input wire [31:0] host_wdata,
    output wire host_ready,
    output wire [31:0] host_rdata,
    output wire host_error,
    output wire busy, done, safety_fault,
    output wire [3:0] halted_mask
);
    wire tensor_selected = (host_addr==8'h80) || (host_addr==8'h84) ||
        (host_addr>=8'h90 && host_addr<=8'h9C) ||
        (host_addr>=8'hA0 && host_addr<=8'hAC) ||
        (host_addr>=8'hB0 && host_addr<=8'hEC);
    wire [31:0] base_rdata;
    wire base_ready,base_error;
    wire tensor_reset = reset || (host_valid && host_write &&
                                  host_addr==8'h00 && host_wdata[1]);
    wire tensor_start = host_valid && host_write &&
                        host_addr==8'h80 && host_wdata[0];
    wire tensor_write_a = host_valid && host_write &&
                          host_addr>=8'h90 && host_addr<=8'h9C;
    wire tensor_write_b = host_valid && host_write &&
                          host_addr>=8'hA0 && host_addr<=8'hAC;
    wire [1:0] tensor_row = (host_addr[5:2]);
    wire [3:0] tensor_result_address = host_addr[5:2];
    wire [31:0] tensor_result_data;
    wire tensor_busy,tensor_done;
    reg [31:0] selected_rdata;

    dream_gpu_host_v12 #(.WATCHDOG_LIMIT(WATCHDOG_LIMIT)) base_host(
        .clk(clk),.reset(reset),.host_valid(host_valid && !tensor_selected),
        .host_write(host_write),.host_addr(host_addr),.host_wdata(host_wdata),
        .host_ready(base_ready),.host_rdata(base_rdata),.host_error(base_error),
        .busy(busy),.done(done),.safety_fault(safety_fault),
        .halted_mask(halted_mask)
    );

    dream_gpu_tensor_int8_v16 tensor(
        .clk(clk),.reset(tensor_reset),.start(tensor_start),
        .write_a(tensor_write_a),.write_b(tensor_write_b),
        .row_address(tensor_row),.write_data(host_wdata),
        .result_address(tensor_result_address),
        .result_data(tensor_result_data),.busy(tensor_busy),.done(tensor_done)
    );

    always @* begin
      selected_rdata=base_rdata;
      if (host_addr==8'h80)
        selected_rdata=0;
      else if (host_addr==8'h84)
        selected_rdata={30'b0,tensor_busy,tensor_done};
      else if (host_addr>=8'hB0 && host_addr<=8'hEC)
        selected_rdata=tensor_result_data;
    end

    assign host_ready=host_valid ? (tensor_selected ? 1'b1 : base_ready) : 1'b0;
    assign host_error=tensor_selected ? 1'b0 : base_error;
    assign host_rdata=selected_rdata;
endmodule
