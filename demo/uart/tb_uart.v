`timescale 1ns/1ps
module tb_uart;
    reg clk = 0;
    reg rst_n = 0;
    reg [7:0] data = 0;
    reg valid = 0;
    wire ready, txd, busy;
    uart_tx dut (
        .clk(clk), .rst(!rst_n),
        .s_axis_tdata(data), .s_axis_tvalid(valid),
        .s_axis_tready(ready), .txd(txd), .busy(busy),
        .prescale(16'd2)
    );
    always #5 clk = ~clk;
    task send_byte;
        input [7:0] value;
        begin
            @(negedge clk);
            data = value;
            valid = 1;
            @(posedge clk);
            while (!ready) @(posedge clk);
            @(negedge clk);
            valid = 0;
            wait (!busy);
            repeat (3) @(negedge clk);
        end
    endtask
    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        send_byte(8'h55);
        send_byte(8'h00);
        send_byte(8'hff);
        send_byte(8'ha6);
        repeat (4) @(negedge clk);
        $display("UART stimulus complete");
        $finish;
    end
    initial begin
        #100000;
        $display("FAIL stimulus timeout");
        $finish;
    end
endmodule
