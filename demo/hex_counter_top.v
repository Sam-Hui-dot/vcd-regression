module hex_counter_top #(
    parameter [20:0] CNT_MAX = 21'd2_000_000
)(
    input clk,
    input rst_n,
    input btn_inc,
    output [7:0] seg,
    output [7:0] an
);
    wire btn_clean, btn_pulse;
    wire [3:0] count;
    wire [3:0] an_right;

    btn_debounce #(.CNT_MAX(CNT_MAX)) u_deb (
        .clk(clk), .rst_n(rst_n),
        .btn_in(btn_inc), .btn_clean(btn_clean)
    );

    edge_detect u_edge (
        .clk(clk), .rst_n(rst_n), .sig_in(btn_clean),
        .pos_edge(btn_pulse), .neg_edge()
    );

    counter_mod #(.MOD(16)) u_cnt (
        .clk(clk), .rst_n(rst_n), .en(btn_pulse),
        .count(count), .carry()
    );

    dynamic_display #(.SINGLE_DIGIT(1)) u_disp (
        .clk(clk), .rst_n(rst_n),
        .digit0(count), .digit1(4'd0),
        .digit2(4'd0), .digit3(4'd0),
        .seg(seg), .an(an_right)
    );

    assign an = {4'b0000, an_right};
endmodule
