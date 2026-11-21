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
//
// 【M2 显示策略】画面内容有三种可能，用来把"黑屏"拆成可判定状态：
//   1) 出摄像头实时画面                -> 采集链路与显示链路都正常
//   2) FPGA 内部彩条 + LED2 灭         -> 没有 VSYNC：XCLK/供电/复位/SCCB 失败
//   3) FPGA 内部彩条 + LED2 亮         -> 有同步但无有效像素：窗口/格式/曝光配置错
//   彩条在"连续 1 秒没有写进非零像素"时自动接管，出图后立即切回摄像头。
//   所以上板再也不会只看到纯黑：至少能立刻知道问题在摄像头侧还是显示侧。
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
    wire clk_sys, clk_pix, clk_xclk, locked;

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
    // SCCB 配置
    //======================================================================
    wire       sccb_go, sccb_busy, sccb_done, sccb_ackerr;
    wire       scl_lo, sda_lo;
    wire [15:0] cfg_reg;                  // OV5640 寄存器地址为 16 位
    wire [7:0]  cfg_dat, cfg_err_cnt;
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
    assign ov_xclk = clk_xclk;       // 24MHz（硬件说明 F20 标注 24MHz）
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
    // 摄像头"真的在出图"的判定（pclk 域 -> clk_pix 域）
    //
    // 判据不是"收到 VSYNC"，而是"这一帧里写进了非零像素"。
    // 原因是 VSYNC 正常但像素全 0 也是一种典型故障（曝光上限被压低、
    // 输出格式错），此时屏幕同样是黑的，只看 VSYNC 会误判为"采集正常"。
    //
    // 每来一帧有效数据就翻转一次 alive_tog，同步到 clk_pix 域后检测翻转；
    // 超过约 1 秒没有翻转 -> 认为摄像头没出图 -> 显示 FPGA 内部彩条。
    // 这样"黑屏"这个现象被消除：看到彩条=显示通路好、问题在摄像头侧。
    //======================================================================
    reg wr_nz, alive_tog;
    always @(posedge ov_pclk or negedge rst_n_pclk) begin
        if (!rst_n_pclk) begin
            wr_nz     <= 1'b0;
            alive_tog <= 1'b0;
        end else begin
            if (frame_start) begin
                wr_nz <= 1'b0;                  // 新一帧开始，清空本帧标记
                if (wr_nz) alive_tog <= ~alive_tog;  // 上一帧有非零像素
            end else if (wr_en && (pix != 16'd0)) begin
                wr_nz <= 1'b1;
            end
        end
    end

    // 两级同步 + 边沿检测
    reg tog_s1, tog_s2, tog_s3;
    always @(posedge clk_pix or negedge rst_n_pix) begin
        if (!rst_n_pix) begin
            tog_s1 <= 1'b0;
            tog_s2 <= 1'b0;
            tog_s3 <= 1'b0;
        end else begin
            tog_s1 <= alive_tog;
            tog_s2 <= tog_s1;
            tog_s3 <= tog_s2;
        end
    end

    wire alive_evt = tog_s2 ^ tog_s3;       // 收到一帧有效数据（单拍）

    // 1 秒超时（25MHz）
    localparam [24:0] PAT_TO = 25'd25_000_000;

    reg [24:0] pat_cnt;
    reg        pat_en;

    always @(posedge clk_pix or negedge rst_n_pix) begin
        if (!rst_n_pix) begin
            pat_cnt <= 25'd0;
            pat_en  <= 1'b1;                // 上电先显示彩条，出图后自动切走
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

    //----------------------------------------------------------------------
    // 内部彩条：与摄像头完全无关，用来单独验证 VGA 显示通路
    // 8 条 80 像素竖条（白/黄/青/绿/品红/红/蓝/黑），RGB565 直出
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

    reg [15:0] pat_col_d;
    always @(posedge clk_pix or negedge rst_n_pix) begin
        if (!rst_n_pix) pat_col_d <= 16'd0;
        else            pat_col_d <= pat_col;
    end

    assign vga_data  = de_d ? (pat_en ? pat_col_d : fb_dout) : 16'h0000;
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
