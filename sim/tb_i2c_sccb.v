//==========================================================================
// tb_i2c_sccb.v  —  验证 SCCB 四字节写帧格式
//
// 验证点：
//   T1  一次传输应发出 4 字节：DEV=0x78, ADDR_H=0x30, ADDR_L=0x08, DATA=0x82
//   T2  每字节后有 1 个 ACK 槽，共 4 个（从机拉低 SDA 时 ack_err 保持 0）
//   T3  从机不回 ACK 时，ack_err 必须被置起（否则 LED3 告警失效）
//   T4  busy/done 握手：go 之后 busy 拉高，done 单拍脉冲后 busy 落低
//
// 从机模型：sda_i 恒 0（ACK）或恒 1（NAK），足够覆盖本模块的判据逻辑。
// 监视器：在 SCL 上升沿采样 sda_lo（开漏，sda_lo=1 表示主机拉低 = 数据 0）。
//==========================================================================
`timescale 1ns / 1ps

module tb_i2c_sccb;

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         go = 1'b0;
    reg  [7:0]  dev_a = 8'h78;
    reg  [15:0] reg_a = 16'h3008;
    reg  [7:0]  wdat  = 8'h82;
    reg         sda_i = 1'b0;          // 0 = 从机回 ACK

    wire        scl_lo, sda_lo, busy, ack_err, done;

    integer     errors = 0;
    integer     nbits  = 0;
    integer     nbytes = 0;
    reg  [7:0]  sh     = 8'd0;
    reg         scl_d  = 1'b0;
    reg  [7:0]  cap    = 0;            // 捕获到的字节
    reg  [7:0]  got [0:3];

    // 时钟 50MHz
    always #10 clk = ~clk;

    i2c_sccb #(.DIV(8'd2)) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .go      (go),
        .dev_a   (dev_a),
        .reg_a   (reg_a),
        .wdat    (wdat),
        .scl_lo  (scl_lo),
        .sda_lo  (sda_lo),
        .sda_i   (sda_i),
        .busy    (busy),
        .ack_err (ack_err),
        .done    (done)
    );

    //----------------------------------------------------------------------
    // 监视器：SCL 上升沿（scl_lo 1->0）采样
    // 槽序：0..7 数据, 8 ACK, 9..16 数据, 17 ACK, 18..25, 26 ACK, 27..34, 35 ACK
    //----------------------------------------------------------------------
    always @(posedge clk) begin
        scl_d <= scl_lo;
        if (scl_d && !scl_lo && busy) begin
            if ((nbits % 9) == 8) begin
                cap = sh;
                if (nbytes < 4) got[nbytes] = sh;
                nbytes = nbytes + 1;
            end else begin
                sh = {sh[6:0], ~sda_lo};
            end
            nbits = nbits + 1;
        end
    end

    //----------------------------------------------------------------------
    task run_one;
        begin
            nbits = 0; nbytes = 0; sh = 8'd0;
            @(posedge clk); go <= 1'b1;
            @(posedge clk); go <= 1'b0;
            wait (done);
            @(posedge clk);
        end
    endtask

    initial begin
        $display("==== TB i2c_sccb start ====");
        repeat (5) @(posedge clk);
        rst_n <= 1'b1;
        repeat (5) @(posedge clk);

        // ---------------- T1/T2: 正常传输，从机回 ACK ----------------
        sda_i <= 1'b0;
        run_one;

        $display("[T1] byte0=%02h byte1=%02h byte2=%02h byte3=%02h",
                 got[0], got[1], got[2], got[3]);
        if (nbytes !== 4) begin
            $display("[FAIL] 期望 4 个字节，实际 %0d 个", nbytes);
            errors = errors + 1;
        end else if (got[0] !== 8'h78 || got[1] !== 8'h30 ||
                     got[2] !== 8'h08 || got[3] !== 8'h82) begin
            $display("[FAIL] 帧内容不符：期望 78 30 08 82");
            errors = errors + 1;
        end else begin
            $display("[PASS] T1 四字节帧 = 78 30 08 82");
        end

        if (ack_err !== 1'b0) begin
            $display("[FAIL] T2 从机已回 ACK，但 ack_err=%b", ack_err);
            errors = errors + 1;
        end else begin
            $display("[PASS] T2 ACK 正常，ack_err=0");
        end

        // ---------------- T3: 从机不回 ACK ----------------
        sda_i <= 1'b1;
        run_one;
        if (ack_err !== 1'b1) begin
            $display("[FAIL] T3 从机 NAK，但 ack_err 未置起");
            errors = errors + 1;
        end else begin
            $display("[PASS] T3 NAK 正确报错，ack_err=1");
        end

        // ---------------- T4: 握手 ----------------
        sda_i <= 1'b0;
        @(posedge clk); go <= 1'b1;
        @(posedge clk); go <= 1'b0;
        @(posedge clk);
        if (busy !== 1'b1) begin
            $display("[FAIL] T4 go 之后 busy 未拉高");
            errors = errors + 1;
        end
        wait (done);
        @(posedge clk);
        if (busy !== 1'b0) begin
            $display("[FAIL] T4 done 之后 busy 未落低");
            errors = errors + 1;
        end else if (errors == 0) begin
            $display("[PASS] T4 busy/done 握手正常");
        end

        if (errors == 0) $display("==== TB RESULT: PASS ====");
        else             $display("==== TB RESULT: FAIL (%0d) ====", errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("[FAIL] 超时：状态机未收敛");
        $display("==== TB RESULT: FAIL (timeout) ====");
        $finish;
    end

endmodule
