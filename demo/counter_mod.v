module counter_mod #(
    parameter [4:0] MOD = 5'd16
)(
    input clk,
    input rst_n,
    input en,
    output reg [3:0] count,
    output carry
);
    localparam [3:0] LAST = MOD - 5'd1;

    assign carry = en && (count == LAST);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            count <= 4'd0;
        else if (en) begin
            if (count == LAST)
                count <= 4'd0;
            else
                count <= count + 1'b1;
        end
    end
endmodule
