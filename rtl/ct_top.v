//==========================================================================
// ct_top.v  —  系统顶层（里程碑 M2：采集直显通路）
//
//   OV5640 --DVP--> capture --2x2降采样--> frame_buf(320x240x16)
//                                            |
//                                    VGA 时序 --2x2放大--> RGB565 输出
//
// M2 验收目标：显示器上出现摄像头实时画面，无花屏/无错位/无行场抖动
// M3 起在此文件内接入 vision 子系统（块统计/CCL/追踪/叠加），端口不变
//
// LED 上电自检（低电平点亮，扩展板 LED0~LED3）：
//   LED0 亮 = MMCM 锁定
//   LED1 亮 = OV5640 SCCB 配置完成
//   LED2 亮 = 已收到 VSYNC（摄像头正在出图）
//   LED3 亮 = SCCB 出现过无 ACK（应保持熄灭）
//==========================================================================
`timescale 1ns / 1ps

module ct_top (
    input  wire        clk50,        // N18, 50MHz
    input  wire [3:0]  key_n,        // 预留：M5 接入按键控制
    output wire [3:0]  led_n,

    //---------------- OV5640 ----------------
    output wire        ov_xclk,      // F20, 25MHz
    output wire        ov_rst_n,     // A20, 低有效
    output wire        ov_pwdn,      // H16, 高=掉电
    output wire        ov_scl,       // J18
    inout  wire        ov_sda,       // G20
    input  wire        ov_pclk,      // E19
    input  wire        ov_vsync,     // K17
    input  wire        ov_href,      // F19
    input  wire [7:0]  ov_data,      // B20 B19 C20 H17 D20 D18 H18 D19

    //---------------- VGA ----------------
    output wire [15:0] vga_data,
    output wire        vga_hsync,
    output wire        vga_vsync
);

    //======================================================================
    // 时钟与复位
    //======================================================================
    wire clk_sys, clk_pix, locked;

    reg  por_rst;
    reg  [15:0] por_cnt;

    // MMCM 复位：先拉高，锁定前一直保持
    always @(posedge clk50) begin
        if (por_cnt != 16'hFFFF) begin
            por_cnt <= por_cnt + 16'd1;
            por_rst <= 1'b1;
        end else begin
            por_rst <= 1'b0;
        end
    end

    clk_mmcm u_clk (
        .clk50   (clk50),
        .rst     (por_rst),
        .clk_sys (clk_sys),
        .clk_pix (clk_pix),
        .locked  (locked)
    );

    wire rst50_hi;
    por_reset u_por (
        .clk    (clk50),
        .locked (locked),
        .rst    (rst50_hi)
    );

    wire rst_n50   = ~rst50_hi;
    wire rst_n_pclk, rst_n_pix;

    rst_sync u_rst_pclk (.clk(ov_pclk), .arst(rst50_hi), .rst_n(rst_n_pclk));
    rst_sync u_rst_pix  (.clk(clk_pix), .arst(rst50_hi), .rst_n(rst_n_pix));

    // 摄像头复位释放后再等 20ms 才发 SCCB（OV5640 上电稳定时间）
    reg [19:0] cfg_wait;
    reg        cfg_rst_n;
    always @(posedge clk50) begin
        if (!rst_n50) begin
            cfg_wait  <= 20'd0;
            cfg_rst_n <= 1'b0;
        end else if (cfg_wait != 20'd1_000_000) begin
            cfg_wait  <= cfg_wait + 20'd1;
            cfg_rst_n <= 1'b0;
        end else begin
            cfg_rst_n <= 1'b1;
        end
    end

    //======================================================================
    // SCCB 配置
    //======================================================================
    wire       sccb_go, sccb_busy, sccb_done, sccb_ackerr;
    wire       scl_lo, sda_lo;
    wire [7:0] cfg_reg, cfg_dat, cfg_err_cnt;
    wire       cfg_done;

    i2c_sccb #(.DIV(8'd64)) u_sccb (
        .clk     (clk50),
        .rst_n   (cfg_rst_n),
        .go      (sccb_go),
        .dev_a   (8'h78),
        .reg_a   (cfg_reg),
        .wdat    (cfg_dat),
        .scl_lo  (scl_lo),
        .sda_lo  (sda_lo),
        .sda_i   (ov_sda),
        .busy    (sccb_busy),
        .ack_err (sccb_ackerr),
        .done    (sccb_done)
    );

    ov5640_cfg u_cfg (
        .clk      (clk50),
        .rst_n    (cfg_rst_n),
        .go       (sccb_go),
        .o_reg    (cfg_reg),
        .o_dat    (cfg_dat),
        .busy     (sccb_busy),
        .done     (sccb_done),
        .ack_err  (sccb_ackerr),
        .cfg_done (cfg_done),
        .err_cnt  (cfg_err_cnt)
    );

    assign ov_scl  = scl_lo ? 1'b0 : 1'bz;
    assign ov_sda  = sda_lo ? 1'b0 : 1'bz;
    assign ov_xclk = clk_pix;        // 25MHz（OV5640 支持 6~27MHz）
    assign ov_rst_n = rst_n50;
    assign ov_pwdn  = 1'b0;

    //======================================================================
    // 采集 -> 帧缓存（2x2 点采样降采样到 320x240）
    //======================================================================
    wire [15:0] pix;
    wire        pix_vld;
    wire [9:0]  cx, cy;
    wire        frame_start;

    ov5640_capture u_cap (
        .pclk        (ov_pclk),
        .rst_n       (rst_n_pclk),
        .vsync       (ov_vsync),
        .href        (ov_href),
        .data        (ov_data),
        .pix         (pix),
        .pix_vld     (pix_vld),
        .cx          (cx),
        .cy          (cy),
        .frame_start (frame_start)
    );

    wire wr_en = pix_vld && (cx[0] == 1'b0) && (cy[0] == 1'b0) && (cx < 10'd640) && (cy < 10'd480);

    // 行地址 = 行号 x 320；320 = 256 + 64，用移位加法，避免乘法器与位宽告警
    wire [8:0]  wrow = cy[9:1];
    wire [8:0]  wcol = cx[9:1];
    wire [17:0] wr_addr18 = ({9'd0, wrow} << 8) + ({9'd0, wrow} << 6) + {9'd0, wcol};

    //======================================================================
    // 帧缓存读侧 + VGA 时序（2x2 放大）
    // BRAM 输出延迟 1 拍，de/hsync/vsync 同步延迟 1 拍以保持对齐
    //======================================================================
    wire [9:0] vx, vy;
    wire       de, hs, vs, sof;

    vga_timing u_vga (
        .pix_clk (clk_pix),
        .rst_n   (rst_n_pix),
        .x       (vx),
        .y       (vy),
        .de      (de),
        .hsync   (hs),
        .vsync   (vs),
        .sof     (sof)
    );

    wire [8:0]  rrow = vy[9:1];
    wire [8:0]  rcol = vx[9:1];
    wire [17:0] rd_addr18 = ({9'd0, rrow} << 8) + ({9'd0, rrow} << 6) + {9'd0, rcol};
    wire [15:0] fb_dout;

    frame_buf u_fb (
        .wr_clk  (ov_pclk),
        .wr_en   (wr_en),
        .wr_addr (wr_addr18[16:0]),
        .wr_data (pix),
        .rd_clk  (clk_pix),
        .rd_addr (rd_addr18[16:0]),
        .rd_data (fb_dout)
    );

    reg de_d, hs_d, vs_d;
    always @(posedge clk_pix or negedge rst_n_pix) begin
        if (!rst_n_pix) begin
            de_d <= 1'b0;
            hs_d <= 1'b1;
            vs_d <= 1'b1;
        end else begin
            de_d <= de;
            hs_d <= hs;
            vs_d <= vs;
        end
    end

    assign vga_data  = de_d ? fb_dout : 16'h0000;
    assign vga_hsync = hs_d;
    assign vga_vsync = vs_d;

    //======================================================================
    // LED 自检
    //======================================================================
    reg vs_seen;
    always @(posedge ov_pclk or negedge rst_n_pclk) begin
        if (!rst_n_pclk)          vs_seen <= 1'b0;
        else if (frame_start)     vs_seen <= 1'b1;
    end

    assign led_n[0] = ~locked;
    assign led_n[1] = ~cfg_done;
    assign led_n[2] = ~vs_seen;
    assign led_n[3] = ~(|cfg_err_cnt);

endmodule
