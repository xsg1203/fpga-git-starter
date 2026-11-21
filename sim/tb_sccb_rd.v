//==========================================================================
// tb_sccb_rd.v  —  SCCB 读通路仿真（含过程式 OV5640 从机模型）
//
// 从机模型严格遵循真实器件时序：数据/ACK 只在 SCL 低电平期间建立与释放，
// 因为在 SCL 高电平期间改变 SDA 会被总线解释成 START 或 STOP。
// （第一版模型就是在 SCL 高电平拉低 ACK，被主机判成 START，导致后半段全错。）
//
// 校验点：
//   1. 地址阶段发出 0x78 / 0x30 / 0x0A
//   2. 读地址是 0x79
//   3. rdat 等于从机输出的 0x56（非全 0 也非全 1，能暴露移位方向错误）
//   4. 全程无 NACK
//==========================================================================
`timescale 1ns / 1ps

module tb_sccb_rd;

    reg         clk = 0;
    reg         rst_n = 0;
    reg         go = 0;
    reg  [15:0] reg_a = 16'h300A;

    wire        scl_lo, sda_lo;
    reg         sda_en = 0;
    reg         sda_val = 1;
    wire        sda;
    wire        scl;

    wire        busy, ack_err, done;
    wire [7:0]  rdat;

    assign sda = sda_lo ? 1'b0 :
                 sda_en ? sda_val : 1'bz;
    assign scl = scl_lo ? 1'b0 : 1'b1;
    pullup (sda);

    // 2ns 传输延迟版本，消除零延时竞争
    reg scl_d = 1, sda_d = 1;
    always @(scl) scl_d <= #2 scl;
    always @(sda) sda_d <= #2 sda;

    //---------------- 被测模块 ----------------
    sccb_rd #(.DIV(8'd4)) dut (            // 仿真用 DIV=4 加速
        .clk     (clk),
        .rst_n   (rst_n),
        .go      (go),
        .dev_a   (8'h78),
        .reg_a   (reg_a),
        .scl_lo  (scl_lo),
        .sda_lo  (sda_lo),
        .sda_i   (sda),
        .busy    (busy),
        .ack_err (ack_err),
        .rdat    (rdat),
        .done    (done)
    );

    //---------------- 过程式从机 ----------------
    reg [7:0] q0 = 8'd0, q1 = 8'd0, q2 = 8'd0, q3 = 8'd0;
    reg [7:0] dev_pid = 8'h56;             // 模拟 OV5640 PID 高字节
    integer   i;

    task wait_start;
        begin
            @(negedge sda_d);
            while (scl_d !== 1'b1) @(negedge sda_d);
            $display("[slave] START  t=%0t", $time);
        end
    endtask

    task wait_stop;
        begin
            @(posedge sda_d);
            while (scl_d !== 1'b1) @(posedge sda_d);
            $display("[slave] STOP   t=%0t", $time);
        end
    endtask

    // 收 1 字节（MSB 先行）
    task rx_byte;
        output [7:0] b;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                @(posedge scl_d);
                b[i] = sda_d;
            end
        end
    endtask

    // 回 ACK：SCL 低电平期间拉低，下一个低电平期间释放
    task send_ack;
        begin
            @(negedge scl_d);
            sda_en = 1'b1; sda_val = 1'b0;
            @(posedge scl_d);
            @(negedge scl_d);
            sda_en = 1'b0;
        end
    endtask

    // 输出 1 字节（MSB 先行），随后释放 SDA 让主机发 NACK
    // 注意：进入本任务时 SCL 正处于低电平（上一步 send_ack 的负沿之后），
    //       所以 bit7 要立刻建立，不能等下一个负沿，否则会整体晚一个时钟。
    task tx_byte;
        input [7:0] b;
        begin
            sda_en = 1'b1; sda_val = b[7];
            @(posedge scl_d);
            for (i = 6; i >= 0; i = i - 1) begin
                @(negedge scl_d);
                sda_val = b[i];
                @(posedge scl_d);
            end
            @(negedge scl_d);
            sda_en = 1'b0;                 // 第 9 个时钟释放 -> 主机读到 NACK
        end
    endtask

    initial begin : slave
        sda_en = 1'b0;
        // 第一段：写寄存器地址
        wait_start;
        rx_byte(q0); send_ack;
        rx_byte(q1); send_ack;
        rx_byte(q2); send_ack;
        wait_stop;
        // 第二段：读寄存器
        wait_start;
        rx_byte(q3); send_ack;
        tx_byte(dev_pid);
        wait_stop;
        $display("[slave] done");
    end

    //---------------- 时钟与流程 ----------------
    always #10 clk = ~clk;        // 50MHz

    integer errors = 0;

    initial begin
        rst_n = 0;
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (10) @(posedge clk);

        @(posedge clk);
        go <= 1'b1;
        @(posedge clk);
        go <= 1'b0;

        wait (done === 1'b1);
        repeat (20) @(posedge clk);

        $display("---- SCCB READ TEST ----");
        $display("addr byte  : %02h (expect 78)", q0);
        $display("reg high   : %02h (expect 30)", q1);
        $display("reg low    : %02h (expect 0a)", q2);
        $display("read dev   : %02h (expect 79)", q3);
        $display("read data  : %02h (expect 56)", rdat);
        $display("ack_err    : %0d (expect 0)", ack_err);

        if (q0 !== 8'h78) begin errors = errors + 1; $display("FAIL: dev byte"); end
        if (q1 !== 8'h30) begin errors = errors + 1; $display("FAIL: reg high"); end
        if (q2 !== 8'h0A) begin errors = errors + 1; $display("FAIL: reg low"); end
        if (q3 !== 8'h79) begin errors = errors + 1; $display("FAIL: read dev"); end
        if (rdat !== 8'h56) begin errors = errors + 1; $display("FAIL: read data"); end
        if (ack_err !== 1'b0) begin errors = errors + 1; $display("FAIL: ack_err"); end

        if (errors == 0) $display("PASS: SCCB read path OK");
        else             $display("FAIL: %0d error(s)", errors);

        $finish;
    end

    initial begin
        #200_000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule
