`timescale 1ns/1ps

module tb_hex_counter_top;
    reg clk, rst_n, btn_inc;
    wire [7:0] seg, an;
    wire btn_clean, btn_pulse;
    wire [3:0] count;
    integer i, errors;

    hex_counter_top #(.CNT_MAX(21'd8)) uut (
        .clk(clk), .rst_n(rst_n), .btn_inc(btn_inc),
        .seg(seg), .an(an)
    );

    assign count = uut.count;
    assign btn_clean = uut.btn_clean;
    assign btn_pulse = uut.btn_pulse;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task check_count;
        input [3:0] expected;
        begin
            if (count !== expected || an !== 8'h01) begin
                errors = errors + 1;
                $display("Mismatch at %0t: expected count=%h, got count=%h an=%h",
                         $time, expected, count, an);
            end
        end
    endtask

    task check_seg;
        input [7:0] expected;
        begin
            if (seg !== expected) begin
                errors = errors + 1;
                $display("Segment mismatch at %0t: count=%h expected=%h got=%h",
                         $time, count, expected, seg);
            end
        end
    endtask

    task press_button;
        input [3:0] previous_count, expected_count;
        begin
            btn_inc = 1'b1;
            repeat (2) @(negedge clk);
            btn_inc = 1'b0;
            repeat (3) @(negedge clk);
            check_count(previous_count);
            btn_inc = 1'b1;
            repeat (16) @(negedge clk);
            check_count(expected_count);
            repeat (16) @(negedge clk);
            check_count(expected_count);
            btn_inc = 1'b0;
            repeat (2) @(negedge clk);
            btn_inc = 1'b1;
            repeat (3) @(negedge clk);
            btn_inc = 1'b0;
            repeat (16) @(negedge clk);
            check_count(expected_count);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        btn_inc = 1'b0;
        errors = 0;
        repeat (3) @(negedge clk);
        check_count(4'h0);
        check_seg(8'hFC);
        rst_n = 1'b1;

        for (i = 0; i < 16; i = i + 1) begin
            press_button(i[3:0], i[3:0] + 4'd1);
            case (i)
                8:  check_seg(8'hF6);
                9:  check_seg(8'hEE);
                14: check_seg(8'h8E);
                15: check_seg(8'hFC);
            endcase
        end

        press_button(4'h0, 4'h1);
        #2;
        rst_n = 1'b0;
        #1;
        check_count(4'h0);
        check_seg(8'hFC);

        if (errors == 0)
            $display("PASS: press, hold, release, hex wrap and reset.");
        else
            $display("FAIL: %0d mismatches.", errors);
        $finish;
    end
endmodule
