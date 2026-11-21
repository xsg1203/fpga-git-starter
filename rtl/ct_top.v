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
//   LED1 亮 = OV5640 SCCB 写序列走完
//   LED2 亮 = 采到过 VSYNC 上升沿（注意：此灯不可作为证据，见下）
//   LED3 亮 = SCCB 写过程中出现过 NACK
//
// 【LED2 为什么不能当证据】
//   若传感器把 DVP 引脚设为输入（0x3017=0x00），FPGA 侧 K17 悬空，
//   噪声边沿同样会置位 vs_seen。所以"LED2 亮"只证明 E19 上有边沿，
//   不证明信号来自摄像头。真正的判据是"有没有写进非零像素"。
//
// 【M2 显示策略】
//   没有有效画面时，屏幕上显示自检面板（diag_osd），而不是纯黑或纯彩条：
//     - 4 行寄存器回读（PID/PAD/电源），绿=相符 红=不符 黄=未读回
//     - 1 行链路状态（SCCB自检 / PCLK / HREF / 非零像素）
//   出图后自动切回摄像头实时画面。
//==========================================================================
`timescale 1ns / 1ps

module ct_top (
    input  wire        clk50,        // N18, 50MHz
    input  wire [3:0]  key_n,        // 预留：M5 接入按键控制
    output wire [3:0]  led_n,

    //---------------- OV5640 ----------------
    output wire        ov_xclk,      // F20, 24MHz
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
    wire clk_sys, clk_pix, clk_xclk, locked;

    reg  por_rst;
    reg  [15:0] por_cnt;

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
        .clk_xclk(clk_xclk),
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
    // SCCB 写配置
    //======================================================================
    wire       sccb_go, sccb_busy, sccb_done, sccb_ackerr;
    wire       scl_lo_wr, sda_lo_wr;
    wire [15:0] cfg_reg;                  // OV5640 寄存器地址为 16 位
    wire [7:0]  cfg_dat, cfg_err_cnt;
    wire       cfg_done;

    // DIV 由 64 放慢到 128：SCL 约 97.6kHz。
    // 教学扩展板通常没有 I2C 上拉，靠 FPGA 内部弱上拉（约 20kΩ），
    // 上升沿较慢，100kHz 比 200kHz 稳定得多。
    i2c_sccb #(.DIV(8'd128)) u_sccb (
        .clk     (clk50),
        .rst_n   (cfg_rst_n),
        .go      (sccb_go),
        .dev_a   (8'h78),
        .reg_a   (cfg_reg),
        .wdat    (cfg_dat),
        .scl_lo  (scl_lo_wr),
        .sda_lo  (sda_lo_wr),
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

    //======================================================================
    // SCCB 回读自检（配置完成后执行一次）
    //
    // 写操作无法自证：从机对每个字节都回 ACK，写错了也看不出来。
    // 唯一能自证的是读回已知常量 —— OV5640 的 PID 固定为 0x5640。
    //======================================================================
    wire        rd_go, rd_busy, rd_ackerr, rd_done;
    wire [7:0]  rd_dat;
    wire [15:0] rd_reg;
    wire        scl_lo_rd, sda_lo_rd;

    reg         cfg_done_d, rb_started;
    always @(posedge clk50 or negedge rst_n50) begin
        if (!rst_n50) begin
            cfg_done_d <= 1'b0;
            rb_started <= 1'b0;
        end else begin
            cfg_done_d <= cfg_done;
            if (cfg_done && !cfg_done_d) rb_started <= 1'b1;
        end
    end
    wire rb_start = cfg_done && !cfg_done_d && !rb_started;

    // 回读值由子模块输出，父层必须是 wire（Verilog-2001 不允许把 output 接到 reg）
    wire [7:0]  v_pidh, v_pidl, v_pad, v_pwr;
    wire [3:0]  rb_ok;
    wire        rb_bad, rb_fin;

    sccb_rd #(.DIV(8'd128)) u_sccb_rd (
        .clk     (clk50),
        .rst_n   (cfg_rst_n),
        .go      (rd_go),
        .dev_a   (8'h78),
        .reg_a   (rd_reg),
        .scl_lo  (scl_lo_rd),
        .sda_lo  (sda_lo_rd),
        .sda_i   (ov_sda),
        .busy    (rd_busy),
        .ack_err (rd_ackerr),
        .rdat    (rd_dat),
        .done    (rd_done)
    );

    ov5640_readback u_rb (
        .clk     (clk50),
        .rst_n   (cfg_rst_n),
        .start   (rb_start),
        .go      (rd_go),
        .reg_a   (rd_reg),
        .busy    (rd_busy),
        .ack_err (rd_ackerr),
        .done    (rd_done),
        .rdat    (rd_dat),
        .v_pidh  (v_pidh),
        .v_pidl  (v_pidl),
        .v_pad   (v_pad),
        .v_pwr   (v_pwr),
        .ok      (rb_ok),
        .bad     (rb_bad),
        .fin     (rb_fin)
    );

    // 两条通路共用总线；读只在写完成之后进行，不会冲突
    wire scl_lo = scl_lo_wr | scl_lo_rd;
    wire sda_lo = sda_lo_wr | sda_lo_rd;

    assign ov_scl   = scl_lo ? 1'b0 : 1'bz;
    assign ov_sda   = sda_lo ? 1'b0 : 1'bz;
    assign ov_xclk  = clk_xclk;      // 24MHz（硬件说明 F20 标注 24MHz）
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
    // "摄像头真的在出图"的判定（pclk 域 -> clk_pix 域）
    //
    // 【为什么不看 VSYNC】上一版用 VSYNC 触发判据，结果 K17 悬空时的噪声
    // 边沿让 LED2 亮、判据也"正常"，反而掩盖了故障。这里改成：
    //   只要写进过非零像素，就认为出图了 —— 与 VSYNC 完全解耦。
    // 计数器每 4096 个非零像素翻一次，同步到 clk_pix 域后检测翻转，
    // 超过约 1 秒无翻转就显示自检面板，出图后立即切回。
    //======================================================================
    reg [15:0] px_cnt;
    reg [15:0] pdiv;
    reg        href_sticky;

    always @(posedge ov_pclk or negedge rst_n_pclk) begin
        if (!rst_n_pclk) begin
            px_cnt      <= 16'd0;
            pdiv        <= 16'd0;
            href_sticky <= 1'b0;
        end else begin
            if (wr_en && (pix != 16'd0)) px_cnt <= px_cnt + 16'd1;
            pdiv <= pdiv + 16'd1;
            if (ov_href) href_sticky <= 1'b1;
        end
    end

    // 两个慢速翻转位：跨域同步时不会出现"每拍都变"的亚稳态问题
    wire px_tog  = px_cnt[12];   // 每 4096 个非零像素翻一次
    wire clk_tog = pdiv[13];     // 每 8192 个 PCLK 翻一次（约 146us @56MHz）

    reg pt_s1, pt_s2;
    reg ct_s1, ct_s2;
    reg hs_s1, hs_s2;
    reg vss_s1, vss_s2;

    reg vs_seen;
    always @(posedge ov_pclk or negedge rst_n_pclk) begin
        if (!rst_n_pclk)      vs_seen <= 1'b0;
        else if (frame_start) vs_seen <= 1'b1;
    end

    reg px_nz;
    reg pclk_alive, href_alive;

    always @(posedge clk_pix or negedge rst_n_pix) begin
        if (!rst_n_pix) begin
            pt_s1 <= 1'b0; pt_s2 <= 1'b0;
            ct_s1 <= 1'b0; ct_s2 <= 1'b0;
            hs_s1 <= 1'b0; hs_s2 <= 1'b0;
            vss_s1 <= 1'b0; vss_s2 <= 1'b0;
            px_nz <= 1'b0;
            pclk_alive <= 1'b0;
            href_alive <= 1'b0;
        end else begin
            pt_s1  <= px_tog;      pt_s2  <= pt_s1;
            ct_s1  <= clk_tog;     ct_s2  <= ct_s1;
            hs_s1  <= href_sticky; hs_s2  <= hs_s1;
            vss_s1 <= vs_seen;     vss_s2 <= vss_s1;

            if (pt_s1 ^ pt_s2) px_nz      <= 1'b1;   // 有过非零像素
            if (ct_s1 ^ ct_s2) pclk_alive <= 1'b1;   // PCLK 在跳
            if (hs_s2)         href_alive <= 1'b1;
        end
    end

    wire alive_evt = pt_s1 ^ pt_s2;

    // 1 秒超时（25MHz）
    localparam [24:0] PAT_TO = 25'd25_000_000;

    reg [24:0] pat_cnt;
    reg        pat_en;

    always @(posedge clk_pix or negedge rst_n_pix) begin
        if (!rst_n_pix) begin
            pat_cnt <= 25'd0;
            pat_en  <= 1'b1;                // 上电先显示自检面板，出图后自动切走
        end else if (alive_evt) begin
            pat_cnt <= 25'd0;
            pat_en  <= 1'b0;
        end else if (pat_cnt != PAT_TO) begin
            pat_cnt <= pat_cnt + 25'd1;
        end else begin
            pat_en  <= 1'b1;
        end
    end

    //======================================================================
    // 帧缓存读侧 + VGA 时序（2x2 放大）
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

    //----------------------------------------------------------------------
    // 内部彩条：与摄像头完全无关，用来单独验证 VGA 显示通路
    //----------------------------------------------------------------------
    reg [15:0] pat_col;
    always @* begin
        if      (vx < 10'd80)  pat_col = 16'hFFFF;   // 白
        else if (vx < 10'd160) pat_col = 16'hFFE0;   // 黄
        else if (vx < 10'd240) pat_col = 16'h07FF;   // 青
        else if (vx < 10'd320) pat_col = 16'h07E0;   // 绿
        else if (vx < 10'd400) pat_col = 16'hF81F;   // 品红
        else if (vx < 10'd480) pat_col = 16'hF800;   // 红
        else if (vx < 10'd560) pat_col = 16'h001F;   // 蓝
        else                   pat_col = 16'h0000;   // 黑
    end

    //----------------------------------------------------------------------
    // 自检面板叠加（只在没有画面时出现，覆盖彩条上部）
    //----------------------------------------------------------------------
    wire [15:0] dg_col;
    wire        dg_en;

    diag_osd u_diag (
        .vx         (vx),
        .vy         (vy),
        .v_pidh     (v_pidh),
        .v_pidl     (v_pidl),
        .v_pad      (v_pad),
        .v_pwr      (v_pwr),
        .ok         (rb_ok),
        .fin        (rb_fin),
        .bad        (rb_bad),
        .pclk_alive (pclk_alive),
        .href_alive (href_alive),
        .vs_seen    (vss_s2),
        .px_nz      (px_nz),
        .col        (dg_col),
        .en         (dg_en)
    );

    // BRAM 输出延迟 1 拍，所有叠加源同样延迟 1 拍以保持对齐
    reg [15:0] pat_col_d, dg_col_d;
    reg        dg_en_d;
    always @(posedge clk_pix or negedge rst_n_pix) begin
        if (!rst_n_pix) begin
            pat_col_d <= 16'd0;
            dg_col_d  <= 16'd0;
            dg_en_d   <= 1'b0;
        end else begin
            pat_col_d <= pat_col;
            dg_col_d  <= dg_col;
            dg_en_d   <= dg_en;
        end
    end

    assign vga_data  = de_d ? (pat_en ? (dg_en_d ? dg_col_d : pat_col_d) : fb_dout)
                            : 16'h0000;
    assign vga_hsync = hs_d;
    assign vga_vsync = vs_d;

    //======================================================================
    // LED 自检
    //======================================================================
    assign led_n[0] = ~locked;
    assign led_n[1] = ~cfg_done;
    assign led_n[2] = ~vs_seen;
    assign led_n[3] = ~(|cfg_err_cnt);

endmodule
