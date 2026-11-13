module btn_debounce #(
    parameter [20:0] CNT_MAX = 21'd2_000_000
)(
    input clk,
    input rst_n,
    input btn_in,
    output reg btn_clean
);
    (* ASYNC_REG = "TRUE" *) reg btn_meta, btn_sync;
    reg [20:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_meta <= 1'b0;
            btn_sync <= 1'b0;
        end else begin
            btn_meta <= btn_in;
            btn_sync <= btn_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt       <= 21'd0;
            btn_clean <= 1'b0;
        end else if (btn_sync == btn_clean) begin
            cnt <= 21'd0;
        end else if (cnt == CNT_MAX - 1'b1) begin
            cnt       <= 21'd0;
            btn_clean <= btn_sync;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end
endmodule
