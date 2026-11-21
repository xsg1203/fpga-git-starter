//==========================================================================
// clk_mmcm.v  —  50MHz 输入 -> 100MHz(clk_sys) + 25MHz(clk_pix) + 24MHz(clk_xclk)
//
// 手写 MMCME2_BASE 原语，避免 IP 工程文件（.xci）进版本库
//
// 【为什么重新算分频】
//   硬件说明明确 OV_XCLK 是 24MHz（F20），而 OV5640 初始化表里 0x3036=0x69
//   的倍频值也是按 24MHz 输入标定的。原设计直接把 25MHz 的 clk_pix 当 XCLK，
//   差 4.17%，会让 PCLK 与帧率同步偏 4%（不致命但没必要时时带着这个偏差）。
//   25MHz 与 24MHz 在 VCO=900MHz 下无法同时用整数分频得到（900/37.5 只能挂在
//   支持小数分频的 CLKOUT0 上），因此把 VCO 改为 600MHz：
//
//     VCO = 50MHz x 12 / 1        = 600.000MHz   (Artix-7 -1 合法范围 600~1200)
//     CLKOUT0 = 600 / 6.000       = 100.000MHz  -> clk_sys（M3 主处理时钟）
//     CLKOUT1 = 600 / 24          =  25.000MHz  -> clk_pix（VGA 640x480@59.5Hz）
//     CLKOUT2 = 600 / 25          =  24.000MHz  -> clk_xclk（OV5640 XCLK）
//
//   三个输出全部为整数分频，无小数分频带来的占空比误差。
//==========================================================================
`timescale 1ns / 1ps

module clk_mmcm (
    input  wire clk50,
    input  wire rst,        // 高有效，来自顶层上电计数
    output wire clk_sys,
    output wire clk_pix,
    output wire clk_xclk,
    output wire locked
);

    wire clkfb_raw, clkfb_buf;
    wire clk_sys_raw, clk_pix_raw, clk_xclk_raw;

    MMCME2_BASE #(
        .CLKIN1_PERIOD      (20.000),
        .REF_JITTER1        (0.010),
        .DIVCLK_DIVIDE      (1),
        .CLKFBOUT_MULT_F    (12.000),   // VCO = 50 * 12 = 600MHz
        .CLKFBOUT_PHASE     (0.0),
        .CLKOUT0_DIVIDE_F   (6.000),    // 100MHz
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .CLKOUT1_DIVIDE     (24),       // 25MHz (VGA)
        .CLKOUT1_DUTY_CYCLE (0.5),
        .CLKOUT1_PHASE      (0.0),
        .CLKOUT2_DIVIDE     (25),       // 24MHz (OV5640 XCLK)
        .CLKOUT2_DUTY_CYCLE (0.5),
        .CLKOUT2_PHASE      (0.0),
        .CLKOUT3_DIVIDE     (1),
        .CLKOUT4_DIVIDE     (1),
        .CLKOUT5_DIVIDE     (1),
        .CLKOUT4_CASCADE    ("FALSE"),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        .CLKIN1    (clk50),
        .CLKFBIN   (clkfb_buf),
        .CLKFBOUT  (clkfb_raw),
        .CLKFBOUTB (),
        .CLKOUT0   (clk_sys_raw),
        .CLKOUT0B  (),
        .CLKOUT1   (clk_pix_raw),
        .CLKOUT1B  (),
        .CLKOUT2   (clk_xclk_raw),
        .CLKOUT2B  (),
        .CLKOUT3   (),
        .CLKOUT3B  (),
        .CLKOUT4   (),
        .CLKOUT5   (),
        .LOCKED    (locked),
        .PWRDWN    (1'b0),
        .RST       (rst)
    );

    BUFG u_bufg_fb   (.I(clkfb_raw),    .O(clkfb_buf));
    BUFG u_bufg_sys  (.I(clk_sys_raw),  .O(clk_sys));
    BUFG u_bufg_pix  (.I(clk_pix_raw),  .O(clk_pix));
    BUFG u_bufg_xclk (.I(clk_xclk_raw), .O(clk_xclk));

endmodule
