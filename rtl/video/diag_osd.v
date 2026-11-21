//==========================================================================
// diag_osd.v  —  摄像头自检叠加层（只在"没有画面"时显示）
//
// 显示内容（640x480 坐标，纯色块，不需要字库）：
//
//   第 0 行（vy 0..31）   0x300A PID 高   [状态块][8 个位格]
//   第 1 行（vy 32..63）  0x300B PID 低   同 上
//   第 2 行（vy 64..95）  0x3017 PAD 方向 同 上
//   第 3 行（vy 96..127） 0x3008 电源状态 同 上
//   第 4 行（vy 128..159）五个链路状态块：
//                          [SCCB 自检][PCLK][HREF][非零像素][VSYNC]
//
// 状态块颜色：绿=与期望值一致，红=不一致，黄=尚未读回
// 位格：白=1，深灰=0，从左到右为 bit7..bit0
//
// 判读方法（第 4 行五格）：
//   * PCLK 红                -> 摄像头根本没时钟输出，查 XCLK/供电/复位
//   * PCLK 绿 / VSYNC 红     -> 有像素时钟但不出帧：流没开、PLL 没起来
//   * PCLK 绿 / VSYNC 绿 / HREF 红 -> 出帧了但 HREF 没进来：引脚/接线/焊点
//   * 前四绿、非零像素红     -> 全在动但数据全 0：输出格式或数据线
//   * 五格全绿仍无图         -> 链路后半段（帧缓存/叠加/时序）
//==========================================================================
`timescale 1ns / 1ps

module diag_osd (
    input  wire [9:0]  vx,
    input  wire [9:0]  vy,
    input  wire [7:0]  v_pidh,
    input  wire [7:0]  v_pidl,
    input  wire [7:0]  v_pad,
    input  wire [7:0]  v_pwr,
    input  wire [3:0]  ok,
    input  wire        fin,
    input  wire        bad,
    input  wire        pclk_alive,
    input  wire        href_alive,
    input  wire        vs_seen,
    input  wire        px_nz,
    output reg  [15:0] col,
    output reg         en
);

    localparam [15:0] C_BG    = 16'h1082;   // 深蓝底
    localparam [15:0] C_GREEN = 16'h07E0;
    localparam [15:0] C_RED   = 16'hF800;
    localparam [15:0] C_YEL   = 16'hFFE0;
    localparam [15:0] C_WHITE = 16'hFFFF;
    localparam [15:0] C_DARK  = 16'h2124;

    // 面板范围：前 160 行
    wire in_panel = (vy < 10'd160);

    //---- 第 0~3 行：寄存器回读 ----
    wire [1:0] row = vy[6:5];                       // 每行 32 像素

    wire [7:0] val = (row == 2'd0) ? v_pidh :
                     (row == 2'd1) ? v_pidl :
                     (row == 2'd2) ? v_pad  : v_pwr;

    wire [7:0] exp = (row == 2'd0) ? 8'h56 :
                     (row == 2'd1) ? 8'h40 :
                     (row == 2'd2) ? 8'hFF : 8'h02;

    wire       row_ok = ok[row];

    // 状态块：x 8..87
    wire in_sq = (vx >= 10'd8) && (vx < 10'd88);

    // 位格：起始 96，格宽 32（24 实心 + 8 间隙）
    wire [9:0] bx    = vx - 10'd96;
    wire       in_bx = (vx >= 10'd96) && (vx < 10'd352);
    wire [2:0] cj    = bx[7:5];
    wire       in_cell = in_bx && (bx[4:0] < 5'd24);
    wire       bitv  = val[3'd7 - cj];

    //---- 第 4 行：链路状态块（x 8..71 / 80..143 / 152..215 / 224..287）----
    wire in_st = (vy >= 10'd128) && (vy < 10'd160);

    always @* begin
        col = C_BG;
        en  = in_panel;

        if (in_panel) begin
            if (in_st) begin
                // ---- 四个状态块 ----
                if (vx >= 10'd8 && vx < 10'd72) begin
                    // SCCB 自检整体：出现 NACK 红；四组读完且无 NACK 绿；否则黄
                    col = bad ? C_RED : (fin ? C_GREEN : C_YEL);
                end else if (vx >= 10'd80 && vx < 10'd144) begin
                    col = pclk_alive ? C_GREEN : C_RED;
                end else if (vx >= 10'd152 && vx < 10'd216) begin
                    col = href_alive ? C_GREEN : C_RED;
                end else if (vx >= 10'd224 && vx < 10'd288) begin
                    col = px_nz ? C_GREEN : C_RED;
                end else if (vx >= 10'd296 && vx < 10'd360) begin
                    // VSYNC 单独一格：缺了它就无法区分"传感器完全没出图"和
                    // "出图了但 HREF 没接进来"，这两种原因的修法完全不同。
                    col = vs_seen ? C_GREEN : C_RED;
                end else begin
                    col = C_BG;
                end
            end else begin
                // ---- 寄存器行 ----
                if (in_sq) begin
                    if (!row_ok)      col = C_YEL;
                    else if (val == exp) col = C_GREEN;
                    else              col = C_RED;
                end else if (in_cell) begin
                    col = bitv ? C_WHITE : C_DARK;
                end else begin
                    col = C_BG;
                end
            end
        end else begin
            col = 16'h0000;
            en  = 1'b0;
        end
    end

endmodule
