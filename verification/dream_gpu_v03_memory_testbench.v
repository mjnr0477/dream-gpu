`timescale 1ns/1ps

module dream_gpu_v03_memory_testbench;

    reg clk;
    reg [3:0] we;
    reg [31:0] addr;
    reg [63:0] wdata;
    wire [63:0] rdata;

    integer errors;

    dream_gpu_memory dut (
        .clk(clk),
        .we(we),
        .addr(addr),
        .wdata(wdata),
        .rdata(rdata)
    );

    always #5 clk = ~clk;

    task write_all;
        input [31:0] addresses;
        input [63:0] values;
        begin
            @(negedge clk);
            addr = addresses;
            wdata = values;
            we = 4'b1111;
            @(posedge clk);
            #1;
            @(negedge clk);
            we = 4'b0000;
        end
    endtask

    task check_data;
        input [31:0] addresses;
        input [63:0] expected;
        input [255:0] label;
        begin
            @(negedge clk);
            addr = addresses;
            #1;
            if (rdata !== expected) begin
                $display("FAIL: %0s", label);
                $display("Expected: %h", expected);
                $display("Actual:   %h", rdata);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s", label);
            end
        end
    endtask

    initial begin
        clk = 0;
        we = 0;
        addr = 0;
        wdata = 0;
        errors = 0;

        $dumpfile("simulation/dream_gpu_v03_memory.vcd");
        $dumpvars(0, dream_gpu_v03_memory_testbench);

        $display("");
        $display("DREAM GPU v0.3 MEMORY VERIFICATION");
        $display("==================================");

        // Four independent writes at four independent addresses.
        write_all(
            {8'd40, 8'd30, 8'd20, 8'd10},
            {16'h4444, 16'h3333, 16'h2222, 16'h1111}
        );

        check_data(
            {8'd40, 8'd30, 8'd20, 8'd10},
            {16'h4444, 16'h3333, 16'h2222, 16'h1111},
            "Four-lane simultaneous write and read"
        );

        // Write and read the first and last addresses.
        write_all(
            {8'd255, 8'd255, 8'd0, 8'd0},
            {16'hABCD, 16'h9876, 16'h5678, 16'h1234}
        );

        check_data(
            {8'd255, 8'd255, 8'd0, 8'd0},
            {16'hABCD, 16'h9876, 16'h5678, 16'h1234},
            "Memory boundary addresses"
        );

        // Overwrite data at existing addresses.
        write_all(
            {8'd40, 8'd30, 8'd20, 8'd10},
            {16'hAAAA, 16'hBBBB, 16'hCCCC, 16'hDDDD}
        );

        check_data(
            {8'd40, 8'd30, 8'd20, 8'd10},
            {16'hAAAA, 16'hBBBB, 16'hCCCC, 16'hDDDD},
            "Memory overwrite"
        );

        // Disable writes and verify stored values remain unchanged.
        @(negedge clk);
        we = 0;
        addr = {8'd40, 8'd30, 8'd20, 8'd10};
        wdata = 64'hFFFFFFFFFFFFFFFF;
        #1;

        if (rdata !==
            {16'hAAAA, 16'hBBBB, 16'hCCCC, 16'hDDDD}) begin
            $display("FAIL: Write protection");
            errors = errors + 1;
        end else begin
            $display("PASS: Disabled writes preserve stored data");
        end

        $display("");
        $display("==================================");

        if (errors == 0) begin
            $display("ALL DREAM GPU v0.3 MEMORY TESTS PASSED");
        end else begin
            $display("MEMORY TEST FAILURES: %0d", errors);
            $fatal(1, "DREAM GPU v0.3 verification failed");
        end

        $display("==================================");
        $finish;
    end

endmodule
