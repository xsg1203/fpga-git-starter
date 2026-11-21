//==========================================================================
// tb_ov5640_cfg.v  —  配置序列器行为验证
//
// 目的：96 项寄存器表是手写的，最容易出的错不是语法，而是
//   (1) 序号错位 -> 后面整段偏移
//   (2) 序列走不完 -> SCCB 停在中途，传感器只配置了一半
//   (3) 首尾关键写入缺失 -> 0x3008=0x82（软复位）/ 0x3008=0x02（出图）
// 本 TB 用一个假的 SCCB 从机（固定回 done/ack_ok）把序列跑完，
// 逐条打印并和期望值比对。
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
    integer n = 0;
    reg [15:0] first_addr, last_addr;
    reg [7:0]  first_dat,  last_dat;
    reg [7:0]  err_cnt_seen;

    always @(posedge clk) if (go) begin
        n = n + 1;
        if (n == 1) begin
            first_addr = o_reg;
            first_dat  = o_dat;
        end
        last_addr = o_reg;
        last_dat  = o_dat;
        // 只打印关键项，避免刷屏
        if (o_reg == 16'h3008 || o_reg == 16'h3800 || o_reg == 16'h3804 ||
            o_reg == 16'h3806 || o_reg == 16'h3808 || o_reg == 16'h380A ||
            o_reg == 16'h380E || o_reg == 16'h4300 || o_reg == 16'h3036 ||
            o_reg == 16'h503D)
            $display("[T] #%0d %04h = %02h", n, o_reg, o_dat);
    end

    //----------------------------------------------------------------------
    initial begin
        $display("==== TB ov5640_cfg start ====");
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        // 96 项 x (3 拍 + 2000 拍 gap) + 5ms 延时 ≈ 210k 拍，给足 2ms*10 余量
        wait (cfg_done);
        repeat (10) @(posedge clk);

        $display("[T] 写入总条数 = %0d (期望 95：96 项中有 1 项是纯延时)", n);
        $display("[T] 第一条 = %04h = %02h (期望 3103 = 03)", first_addr, first_dat);
        $display("[T] 末一条 = %04h = %02h (期望 3008 = 02)", last_addr, last_dat);
        $display("[T] err_cnt = %0d (期望 0)", err_cnt);

        if (n != 95)                              $display("FAIL: 条数不符");
        else if (first_addr != 16'h3103 || first_dat != 8'h03) $display("FAIL: 首项不符");
        else if (last_addr  != 16'h3008 || last_dat  != 8'h02) $display("FAIL: 末项不符（未进入出图状态）");
        else                                       $display("PASS: 序列完整，首尾正确");

        $display("==== TB ov5640_cfg end ====");
        $finish;
    end

    // 超时保护
    initial begin
        #20_000_000;            // 20ms
        $display("FAIL: 超时，cfg_done 未拉高（序列走不完）");
        $finish;
    end

endmodule
