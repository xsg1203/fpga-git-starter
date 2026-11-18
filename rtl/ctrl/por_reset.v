//==========================================================================
// por_reset.v / rst_sync.v  —  上电复位与跨域复位同步
// 板上无复位按键：用计数器产生 ~1.3ms 复位，且以 MMCM locked 为释放条件
//==========================================================================
`timescale 1ns / 1ps

module por_reset #(
    parameter [15:0] POR_CNT = 16'hFFFF      // 50MHz 下 65535 拍 ≈ 1.31ms
) (
    input  wire clk,
    input  wire locked,
    output reg  rst          // 高有效
);

    reg [15:0] cnt;

    always @(posedge clk) begin
        if (!locked) begin
            cnt <= 16'd0;
            rst <= 1'b1;
        end else if (cnt != POR_CNT) begin
            cnt <= cnt + 16'd1;
            rst <= 1'b1;
        end else begin
            rst <= 1'b0;
        end
    end

endmodule

//--------------------------------------------------------------------------
// 异步复位、同步释放。每个非 clk50 时钟域各用一份。
//--------------------------------------------------------------------------
module rst_sync (
    input  wire clk,
    input  wire arst,        // 高有效，异步
    output wire rst_n
);

    reg [1:0] sr;

    always @(posedge clk or posedge arst) begin
        if (arst) sr <= 2'b00;
        else      sr <= {sr[0], 1'b1};
    end

    assign rst_n = sr[1];

endmodule
