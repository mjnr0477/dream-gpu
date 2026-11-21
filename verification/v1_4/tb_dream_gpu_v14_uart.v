`timescale 1ns/1ps
module tb_dream_gpu_v14_uart;
    localparam integer CLKS_PER_BIT=16;
    localparam integer BIT_NS=160;
    reg clk=0, reset=1, uart_rx=1;
    wire uart_tx, busy, done, safety_fault;
    wire [3:0] halted_mask;
    reg [7:0] rx_byte;
    reg [31:0] read_value;
    integer i;

    always #5 clk=~clk;
    always @(posedge clk) begin
        if (dut.rx_valid) $display("RX byte=%02x parser_state=%0d",dut.rx_data,dut.state);
        if (dut.state==8) $display("HOST EXECUTE write=%0d addr=%02x data=%08x",dut.is_write,dut.address,dut.write_data);
    end

    dream_gpu_uart_host_v14 #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut(
        .clk(clk),.reset(reset),.uart_rx(uart_rx),.uart_tx(uart_tx),
        .busy(busy),.done(done),.safety_fault(safety_fault),
        .halted_mask(halted_mask)
    );

    task send_byte(input [7:0] value);
    begin
        uart_rx=0; #(BIT_NS);
        for (i=0;i<8;i=i+1) begin
            uart_rx=value[i]; #(BIT_NS);
        end
        uart_rx=1; #(BIT_NS);
    end
    endtask

    task receive_byte(output [7:0] value);
    integer j;
    begin
        @(negedge uart_tx);
        #(BIT_NS/2);
        if (uart_tx!==0) $fatal(1,"UART start bit invalid");
        for (j=0;j<8;j=j+1) begin
            #(BIT_NS);
            value[j]=uart_tx;
        end
        #(BIT_NS);
        if (uart_tx!==1) $fatal(1,"UART stop bit invalid");
    end
    endtask

    task write_register(input [7:0] address,input [31:0] value);
    reg [7:0] status;
    begin
        $display("SEND WRITE addr=%02x value=%08x",address,value);
        send_byte(8'hD5); send_byte(8'hA5);
        send_byte(8'h02); send_byte(address);
        send_byte(value[7:0]); send_byte(value[15:8]);
        send_byte(value[23:16]); send_byte(value[31:24]);
        receive_byte(status);
        if (status!==0) $fatal(1,"UART write status failure");
    end
    endtask

    task read_register(input [7:0] address,output [31:0] value);
    reg [7:0] status,b0,b1,b2,b3;
    begin
        $display("SEND READ addr=%02x",address);
        send_byte(8'hD5); send_byte(8'hA5);
        send_byte(8'h01); send_byte(address);
        receive_byte(status);
        receive_byte(b0); receive_byte(b1);
        receive_byte(b2); receive_byte(b3);
        if (status!==0) $fatal(1,"UART read status failure");
        value={b3,b2,b1,b0};
    end
    endtask

    initial begin
        repeat(5) @(posedge clk);
        reset=0;
        repeat(5) @(posedge clk);
        write_register(8'h30,32'h000000C7);
        write_register(8'h34,32'h00000028);
        write_register(8'h38,32'h00000001);
        read_register(8'h3C,read_value);
        if (read_value!==32'd40)
            $fatal(1,"UART private-memory readback expected 40, got %0d",read_value);
        $display("PASS: UART host writes and reads lane-private memory");
        $display("DREAM GPU v1.4 UART HOST BRIDGE TEST PASS");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1,"UART host bridge test timeout");
    end
endmodule
