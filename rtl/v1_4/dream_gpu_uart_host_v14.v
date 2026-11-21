`timescale 1ns/1ps

// 8-N-1 UART receiver. CLKS_PER_BIT is the system-clock cycles per UART bit.
module dream_gpu_uart_rx_v14 #(
    parameter integer CLKS_PER_BIT = 434
)(
    input wire clk, reset, rx,
    output reg [7:0] data,
    output reg valid
);
    localparam IDLE=2'd0, START=2'd1, DATA=2'd2, STOP=2'd3;
    reg [1:0] state;
    integer count;
    reg [2:0] bit_index;
    reg [7:0] shift;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state<=IDLE; count<=0; bit_index<=0; shift<=0;
            data<=0; valid<=0;
        end else begin
            valid<=0;
            case(state)
                IDLE: if (!rx) begin
                    state<=START;
                    count<=CLKS_PER_BIT/2;
                end
                START: if (count==0) begin
                    if (!rx) begin
                        state<=DATA;
                        count<=CLKS_PER_BIT-1;
                        bit_index<=0;
                    end else state<=IDLE;
                end else count<=count-1;
                DATA: if (count==0) begin
                    shift[bit_index]<=rx;
                    count<=CLKS_PER_BIT-1;
                    if (bit_index==7) state<=STOP;
                    else bit_index<=bit_index+1'b1;
                end else count<=count-1;
                STOP: if (count==0) begin
                    if (rx) begin
                        data<=shift;
                        valid<=1;
                    end
                    state<=IDLE;
                end else count<=count-1;
                default: state<=IDLE;
            endcase
        end
    end
endmodule

module dream_gpu_uart_tx_v14 #(
    parameter integer CLKS_PER_BIT = 434
)(
    input wire clk, reset,
    input wire [7:0] data,
    input wire start,
    output reg tx,
    output reg busy
);
    localparam IDLE=2'd0, START=2'd1, DATA=2'd2, STOP=2'd3;
    reg [1:0] state;
    integer count;
    reg [2:0] bit_index;
    reg [7:0] data_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state<=IDLE; count<=0; bit_index<=0;
            data_reg<=0; tx<=1; busy<=0;
        end else begin
            case(state)
                IDLE: begin
                    tx<=1; busy<=0;
                    if (start) begin
                        data_reg<=data;
                        tx<=0;
                        busy<=1;
                        count<=CLKS_PER_BIT-1;
                        state<=START;
                    end
                end
                START: if (count==0) begin
                    tx<=data_reg[0];
                    bit_index<=0;
                    count<=CLKS_PER_BIT-1;
                    state<=DATA;
                end else count<=count-1;
                DATA: if (count==0) begin
                    count<=CLKS_PER_BIT-1;
                    if (bit_index==7) begin
                        tx<=1;
                        state<=STOP;
                    end else begin
                        bit_index<=bit_index+1'b1;
                        tx<=data_reg[bit_index+1'b1];
                    end
                end else count<=count-1;
                STOP: if (count==0) begin
                    tx<=1; busy<=0; state<=IDLE;
                end else count<=count-1;
                default: begin state<=IDLE; tx<=1; busy<=0; end
            endcase
        end
    end
endmodule

// Packet format: D5 A5 CMD ADDR [DATA0 DATA1 DATA2 DATA3 for writes].
// CMD 01=read, 02=write. Data is little-endian. Response: STATUS byte
// (00=success); reads append four little-endian data bytes.
module dream_gpu_uart_host_v14 #(
    parameter integer CLKS_PER_BIT = 434,
    parameter integer WATCHDOG_LIMIT = 100000
)(
    input wire clk, reset,
    input wire uart_rx,
    output wire uart_tx,
    output wire busy, done, safety_fault,
    output wire [3:0] halted_mask
);
    wire [7:0] rx_data;
    wire rx_valid;
    reg [7:0] tx_data;
    reg tx_start;
    wire tx_busy;

    dream_gpu_uart_rx_v14 #(.CLKS_PER_BIT(CLKS_PER_BIT)) receiver(
        .clk(clk),.reset(reset),.rx(uart_rx),.data(rx_data),.valid(rx_valid)
    );
    dream_gpu_uart_tx_v14 #(.CLKS_PER_BIT(CLKS_PER_BIT)) transmitter(
        .clk(clk),.reset(reset),.data(tx_data),.start(tx_start),.tx(uart_tx),.busy(tx_busy)
    );

    reg [4:0] state;
    localparam IDLE=0, SYNC2=1, COMMAND=2, ADDRESS=3,
      WD0=4, WD1=5, WD2=6, WD3=7, EXECUTE=8,
      STATUS_START=9, STATUS_BUSY=10, STATUS_DONE=11,
      DATA_START=12, DATA_BUSY=13, DATA_DONE=14;
    reg is_write;
    reg [7:0] address;
    reg [31:0] write_data, read_data;
    reg [2:0] response_index;
    reg [31:0] host_rdata_latched;

    reg host_valid, host_write;
    reg [7:0] host_addr;
    reg [31:0] host_wdata;
    wire [31:0] host_rdata;
    wire host_ready, host_error;

    dream_gpu_host_v12 #(.WATCHDOG_LIMIT(WATCHDOG_LIMIT)) host(
        .clk(clk),.reset(reset),
        .host_valid(host_valid),.host_write(host_write),
        .host_addr(host_addr),.host_wdata(host_wdata),
        .host_ready(host_ready),.host_rdata(host_rdata),.host_error(host_error),
        .busy(busy),.done(done),.safety_fault(safety_fault),
        .halted_mask(halted_mask)
    );

    always @* begin
        host_valid=(state==EXECUTE);
        host_write=is_write;
        host_addr=address;
        host_wdata=write_data;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state<=IDLE; is_write<=0; address<=0; write_data<=0;
            read_data<=0; response_index<=0; host_rdata_latched<=0;
            tx_data<=0; tx_start<=0;
        end else begin
            tx_start<=0;
            case(state)
                IDLE: if (rx_valid && rx_data==8'hD5) state<=SYNC2;
                SYNC2: if (rx_valid) begin
                    if (rx_data==8'hA5) state<=COMMAND;
                    else if (rx_data==8'hD5) state<=SYNC2;
                    else state<=IDLE;
                end
                COMMAND: if (rx_valid) begin
                    if (rx_data==8'h01) begin is_write<=0; state<=ADDRESS; end
                    else if (rx_data==8'h02) begin is_write<=1; state<=ADDRESS; end
                    else state<=IDLE;
                end
                ADDRESS: if (rx_valid) begin
                    address<=rx_data;
                    if (is_write) state<=WD0;
                    else state<=EXECUTE;
                end
                WD0: if (rx_valid) begin write_data[7:0]<=rx_data; state<=WD1; end
                WD1: if (rx_valid) begin write_data[15:8]<=rx_data; state<=WD2; end
                WD2: if (rx_valid) begin write_data[23:16]<=rx_data; state<=WD3; end
                WD3: if (rx_valid) begin write_data[31:24]<=rx_data; state<=EXECUTE; end
                EXECUTE: begin
                    host_rdata_latched<=host_rdata;
                    state<=STATUS_START;
                end
                STATUS_START: if (!tx_busy) begin
                    tx_data<=8'h00; tx_start<=1; state<=STATUS_BUSY;
                end
                STATUS_BUSY: if (tx_busy) state<=STATUS_DONE;
                STATUS_DONE: if (!tx_busy) begin
                    if (is_write) state<=IDLE;
                    else begin response_index<=0; state<=DATA_START; end
                end
                DATA_START: if (!tx_busy) begin
                    case(response_index)
                        0: tx_data<=host_rdata_latched[7:0];
                        1: tx_data<=host_rdata_latched[15:8];
                        2: tx_data<=host_rdata_latched[23:16];
                        default: tx_data<=host_rdata_latched[31:24];
                    endcase
                    tx_start<=1; state<=DATA_BUSY;
                end
                DATA_BUSY: if (tx_busy) state<=DATA_DONE;
                DATA_DONE: if (!tx_busy) begin
                    if (response_index==3) state<=IDLE;
                    else begin response_index<=response_index+1'b1; state<=DATA_START; end
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
