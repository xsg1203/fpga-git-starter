//==========================================================================
// vga_timing.v  —  640x480@60Hz 时序（像素时钟 25MHz -> 实际 59.5Hz）
// H: 640 可见 + 16 前肩 + 96 同步 + 48 后肩 = 800
// V: 480 可见 + 10 前肩 +  2 同步 + 33 后肩 = 525
// 同步信号低有效
//==========================================================================
`timescale 1ns / 1ps

module vga_timing (
    input  wire       pix_clk,
    input  wire       rst_n,
    output reg  [9:0] x,
    output reg  [9:0] y,
    output wire       de,
    output wire       hsync,
    output wire       vsync,
    output wire       sof          // 帧首单拍
);

    localparam [9:0] H_VIS  = 10'd640,
                     H_FP   = 10'd16,
                     H_SYNC = 10'd96,
                     H_BP   = 10'd48,
                     H_TOT  = 10'd800,
                     V_VIS  = 10'd480,
                     V_FP   = 10'd10,
                     V_SYNC = 10'd2,
                     V_BP   = 10'd33,
                     V_TOT  = 10'd525;

    always @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 10'd0;
            y <= 10'd0;
        end else if (x == H_TOT - 10'd1) begin
            x <= 10'd0;
            if (y == V_TOT - 10'd1) y <= 10'd0;
            else                    y <= y + 10'd1;
        end else begin
            x <= x + 10'd1;
        end
    end

    assign de    = (x < H_VIS) && (y < V_VIS);
    assign hsync = ~((x >= H_VIS + H_FP) && (x < H_VIS + H_FP + H_SYNC));
    assign vsync = ~((y >= V_VIS + V_FP) && (y < V_VIS + V_FP + V_SYNC));
    assign sof   = (x == 10'd0) && (y == 10'd0);

endmodule
