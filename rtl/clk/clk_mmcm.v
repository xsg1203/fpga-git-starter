//==========================================================================
// clk_mmcm.v  —  50MHz -> 100MHz(clk_sys) + 25MHz(clk_pix)
// 手写 MMCME2_BASE 原语，避免 IP 工程文件（.xci）进版本库
// VCO = 50/1*18 = 900MHz (Artix-7 -1: 600~1200MHz 合法)
//   CLKOUT0 = 900/9.000 = 100.000MHz
//   CLKOUT1 = 900/36    =  25.000MHz  (VGA 640x480@59.5Hz，全兼容)
//==========================================================================
`timescale 1ns / 1ps

module clk_mmcm (
    input  wire clk50,
    input  wire rst,        // 高有效，来自 por_reset
    output wire clk_sys,
    output wire clk_pix,
    output wire locked
);

    wire clkfb_raw, clkfb_buf;
    wire clk_sys_raw, clk_pix_raw;

    MMCME2_BASE #(
        .CLKIN1_PERIOD      (20.000),
        .REF_JITTER1        (0.010),
        .DIVCLK_DIVIDE      (1),
        .CLKFBOUT_MULT_F    (18.000),
        .CLKFBOUT_PHASE     (0.0),
        .CLKOUT0_DIVIDE_F   (9.000),
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .CLKOUT1_DIVIDE     (36),
        .CLKOUT1_DUTY_CYCLE (0.5),
        .CLKOUT1_PHASE      (0.0),
        .CLKOUT2_DIVIDE     (36),
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
        .CLKOUT2   (),
        .CLKOUT2B  (),
        .CLKOUT3   (),
        .CLKOUT3B  (),
        .CLKOUT4   (),
        .CLKOUT5   (),
        .LOCKED    (locked),
        .PWRDWN    (1'b0),
        .RST       (rst)
    );

    BUFG u_bufg_fb  (.I(clkfb_raw),   .O(clkfb_buf));
    BUFG u_bufg_sys (.I(clk_sys_raw), .O(clk_sys));
    BUFG u_bufg_pix (.I(clk_pix_raw), .O(clk_pix));

endmodule
