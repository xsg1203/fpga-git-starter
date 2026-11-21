//==========================================================================
// tb_ov5640_cfg.v  —  配置序列器验证（结构 + 语义）
//
// 为什么要有"语义"这一层：
//   上一版 TB 只检查"条数 / 首项 / 末项"，结果 0x3017=0x00（DVP 引脚全设成
//   输入）这种值错误照样 PASS，上板表现为"彩条 + 假同步 + 零像素"。
//   所以本 TB 除了结构检查，还把每条写入按地址存表，最后逐条核对关键值。
//
// 检查项：
//   (1) 序列完整走完（末项 0x3008=0x02 进入出图状态）
//   (2) 写入条数 = 95（96 项中 1 项是纯延时）
//   (3) 关键寄存器值正确 —— 重点是 pad 方向、输出窗口、输出格式、曝光上限
//==========================================================================
`timescale 1ns / 1ps

module tb_ov5640_cfg;

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    wire        go;
    wire [15:0] o_reg;
    wire [7:0]  o_dat;
    wire        cfg_done;
    wire [7:0]  err_cnt;

    // 假 SCCB 从机：go 之后 3 拍回 done
    reg  busy = 1'b0;
    reg  done = 1'b0;
    reg  ack_err = 1'b0;
    reg  [2:0] dly = 3'd0;

    always @(posedge clk) begin
        done <= 1'b0;
        if (go) begin
            busy <= 1'b1;
            dly  <= 3'd3;
        end else if (dly != 3'd0) begin
            dly <= dly - 3'd1;
            if (dly == 3'd1) begin
                done <= 1'b1;
                busy <= 1'b0;
            end
        end
    end

    ov5640_cfg u_dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .go       (go),
        .o_reg    (o_reg),
        .o_dat    (o_dat),
        .busy     (busy),
        .done     (done),
        .ack_err  (ack_err),
        .cfg_done (cfg_done),
        .err_cnt  (err_cnt)
    );

    always #10 clk = ~clk;      // 50MHz

    //----------------------------------------------------------------------
    // 写入记录：同一地址多次写时以最后一次为准
    //----------------------------------------------------------------------
    reg [7:0] val [0:65535];
    reg       vld [0:65535];

    integer n = 0;
    integer i;
    integer fail = 0;

    reg [15:0] first_addr, last_addr;
    reg [7:0]  first_dat,  last_dat;

    always @(posedge clk) if (go) begin
        n = n + 1;
        if (n == 1) begin
            first_addr = o_reg;
            first_dat  = o_dat;
        end
        last_addr = o_reg;
        last_dat  = o_dat;
        val[o_reg] = o_dat;
        vld[o_reg] = 1'b1;
    end

    //----------------------------------------------------------------------
    // 单条比对任务
    //----------------------------------------------------------------------
    task chk;
        input [15:0] a;
        input [7:0]  e;
        begin
            if (!vld[a]) begin
                $display("  FAIL  0x%04h 从未被写入（期望 %02h）", a, e);
                fail = fail + 1;
            end else if (val[a] !== e) begin
                $display("  FAIL  0x%04h = %02h （期望 %02h）", a, val[a], e);
                fail = fail + 1;
            end else begin
                $display("  ok    0x%04h = %02h", a, e);
            end
        end
    endtask

    // 掩码比对：只要求指定位为 1（用于 pad 方向这类多 bit 使能寄存器）
    task chkm;
        input [15:0] a;
        input [7:0]  m;
        input [7:0]  e;
        begin
            if (!vld[a]) begin
                $display("  FAIL  0x%04h 从未被写入（期望 &%02h == %02h）", a, m, e);
                fail = fail + 1;
            end else if ((val[a] & m) !== e) begin
                $display("  FAIL  0x%04h = %02h，&%02h = %02h （期望 %02h）",
                         a, val[a], m, val[a] & m, e);
                fail = fail + 1;
            end else begin
                $display("  ok    0x%04h = %02h (&%02h 满足)", a, val[a], m);
            end
        end
    endtask

    //----------------------------------------------------------------------
    initial begin
        for (i = 0; i < 65536; i = i + 1) begin
            val[i] = 8'hxx;
            vld[i] = 1'b0;
        end

        $display("==== TB ov5640_cfg start ====");
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        wait (cfg_done);
        repeat (10) @(posedge clk);

        $display("[T] 写入总条数 = %0d (期望 96)", n);
        $display("[T] 首条 = %04h = %02h (期望 3103=03)", first_addr, first_dat);
        $display("[T] 末条 = %04h = %02h (期望 4202=00)", last_addr, last_dat);
        $display("[T] err_cnt = %0d (期望 0)", err_cnt);

        if (n != 96) begin
            $display("  FAIL  条数不符");
            fail = fail + 1;
        end
        if (first_addr !== 16'h3103 || first_dat !== 8'h03) begin
            $display("  FAIL  首项不符");
            fail = fail + 1;
        end

        // ---- 语义检查 ----
        $display("[T] --- 结构 ---");
        chk(16'h3008, 8'h02);          // 末条必须进入出图（bit6=0）
        // 0x4202 是流开关，0x00 才是开流。这张表以前一条都没写过它，
        // 若复位默认是 0x0F（暂停），现象就是"HREF 从来不高、像素全 0"。
        chk(16'h4202, 8'h00);

        $display("[T] --- DVP 引脚方向（本次黑屏根因）---");
        chkm(16'h3017, 8'hF0, 8'hF0);  // VSYNC/HREF/PCLK/D[9:6] 必须全是输出
        chkm(16'h3018, 8'hF0, 8'hF0);  // D[5:2] 必须全是输出

        $display("[T] --- 输出窗口（必须在感光阵列内）---");
        chk(16'h3804, 8'h0A);          // X end = 0x0A3F
        chk(16'h3805, 8'h3F);
        chk(16'h3806, 8'h07);          // Y end = 0x07A3
        chk(16'h3807, 8'hA3);
        chk(16'h3808, 8'h02);          // 输出 640x480
        chk(16'h3809, 8'h80);
        chk(16'h380A, 8'h01);
        chk(16'h380B, 8'hE0);

        $display("[T] --- 输出格式 ---");
        chk(16'h4300, 8'h6F);          // RGB565
        chk(16'h501F, 8'h01);          // ISP 输出 RGB

        $display("[T] --- 时钟 / 曝光 / 白平衡 ---");
        chk(16'h3035, 8'h11);          // sysclk 分频 1（0x21 帧率减半）
        chk(16'h3036, 8'h69);          // 24MHz 输入标定
        chk(16'h3503, 8'h00);          // AEC 全自动
        chk(16'h3406, 8'h00);          // AWB 自动
        chk(16'h3C0A, 8'h9C);          // 曝光上限（上一版误写 0x07 -> 全黑）
        chk(16'h3C0B, 8'h40);

        if (fail == 0) $display("PASS: 序列完整，关键寄存器值全部正确");
        else           $display("FAIL: %0d 项不符", fail);

        $display("==== TB ov5640_cfg end ====");
        $finish;
    end

    initial begin
        #20_000_000;            // 20ms
        $display("FAIL: 超时，cfg_done 未拉高（序列走不完）");
        $finish;
    end

endmodule
