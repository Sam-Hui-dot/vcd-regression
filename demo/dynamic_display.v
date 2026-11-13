module dynamic_display #(
    parameter PERIOD = 200_000,
    parameter SINGLE_DIGIT = 0
)(
    input clk,
    input rst_n,
    input [3:0] digit0,
    input [3:0] digit1,
    input [3:0] digit2,
    input [3:0] digit3,
    output reg [7:0] seg,
    output [3:0] an
);
    wire [3:0] selected_digit;

    generate
        if (SINGLE_DIGIT) begin : g_single
            assign an = 4'b0001;
            assign selected_digit = digit0;
        end else begin : g_scan
            reg [31:0] div_cnt;
            reg [1:0] scan_cnt;
            reg [3:0] scan_digit;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    div_cnt  <= 32'd0;
                    scan_cnt <= 2'd0;
                end else if (div_cnt == PERIOD - 1) begin
                    div_cnt  <= 32'd0;
                    scan_cnt <= scan_cnt + 1'b1;
                end else begin
                    div_cnt <= div_cnt + 1'b1;
                end
            end

            always @(*) begin
                case (scan_cnt)
                    2'd0: scan_digit = digit0;
                    2'd1: scan_digit = digit1;
                    2'd2: scan_digit = digit2;
                    2'd3: scan_digit = digit3;
                    default: scan_digit = 4'd0;
                endcase
            end

            assign an = 4'b0001 << scan_cnt;
            assign selected_digit = scan_digit;
        end
    endgenerate

    always @(*) begin
        case (selected_digit)
            4'h0: seg = 8'b1111_1100;
            4'h1: seg = 8'b0110_0000;
            4'h2: seg = 8'b1101_1010;
            4'h3: seg = 8'b1111_0010;
            4'h4: seg = 8'b0110_0110;
            4'h5: seg = 8'b1011_0110;
            4'h6: seg = 8'b1011_1110;
            4'h7: seg = 8'b1110_0000;
            4'h8: seg = 8'b1111_1110;
            4'h9: seg = 8'b1111_0110;
            4'hA: seg = 8'b1110_1110;
            4'hB: seg = 8'b0011_1110;
            4'hC: seg = 8'b1001_1100;
            4'hD: seg = 8'b0111_1010;
            4'hE: seg = 8'b1001_1110;
            4'hF: seg = 8'b1000_1110;
            default: seg = 8'b0000_0000;
        endcase
    end
endmodule
