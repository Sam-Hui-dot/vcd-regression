module edge_detect (
    input clk,
    input rst_n,
    input sig_in,
    output pos_edge,
    output neg_edge
);
    reg sig_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sig_d <= 1'b0;
        else
            sig_d <= sig_in;
    end

    assign pos_edge = sig_in & ~sig_d;
    assign neg_edge = ~sig_in & sig_d;
endmodule
