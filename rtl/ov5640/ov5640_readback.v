//==========================================================================
// ov5640_readback.v  —  配置完成后回读 4 个关键寄存器
//
// 目的：把"配没配上"从猜测变成可读的事实。四组值各有明确判据：
//
//   0x300A / 0x300B  PID 高/低   OV5640 固定为 0x56 / 0x40
//                                -> 读不到 = SCCB 链路坏（上拉/接触/器件不在）
//   0x3017           PAD 方向     我们写 0xFF
//                                -> 读回不是 0xFF = 写没落进去
//   0x3008           电源状态      末尾写 0x02（退出 power-down）
//                                -> 读回不是 0x02 = 表没跑完或又被复位
//
// 只在 cfg_done 之后启动一次，不与写通路争总线。
// 两次事务之间插入一段空闲，满足 SCCB 总线空闲时间。
//==========================================================================
`timescale 1ns / 1ps

module ov5640_readback (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,        // 单拍：配置完成后置位
    output reg         go,
    output reg  [15:0] reg_a,
    input  wire        busy,
    input  wire        ack_err,
    input  wire        done,
    input  wire [7:0]  rdat,
    output reg  [7:0]  v_pidh,
    output reg  [7:0]  v_pidl,
    output reg  [7:0]  v_pad,
    output reg  [7:0]  v_pwr,
    output reg  [3:0]  ok,           // 每个寄存器读成功（无 NACK）
    output reg         bad,          // 出现过 NACK
    output reg         fin           // 四组读完
);

    localparam [2:0] S_IDLE  = 3'd0,
                     S_ISSUE = 3'd1,
                     S_WAIT  = 3'd2,
                     S_GAP   = 3'd3,
                     S_FIN   = 3'd4;

    // 寄存器访问顺序（低 2 位是索引）
    function [15:0] reg_of;
        input [1:0] i;
        begin
            case (i)
                2'd0: reg_of = 16'h300A;
                2'd1: reg_of = 16'h300B;
                2'd2: reg_of = 16'h3017;
                default: reg_of = 16'h3008;
            endcase
        end
    endfunction

    reg [2:0]  st;
    reg [1:0]  idx;
    reg [15:0] gapc;

    localparam [15:0] GAP_CYC = 16'd4000;   // 约 80us @50MHz，远大于总线空闲要求

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st      <= S_IDLE;
            idx     <= 2'd0;
            gapc    <= 16'd0;
            go      <= 1'b0;
            reg_a   <= 16'h300A;
            v_pidh  <= 8'd0;
            v_pidl  <= 8'd0;
            v_pad   <= 8'd0;
            v_pwr   <= 8'd0;
            ok      <= 4'd0;
            bad     <= 1'b0;
            fin     <= 1'b0;
        end else begin
            go <= 1'b0;

            case (st)
            S_IDLE: begin
                // fin 必须"粘住"：OSD 每帧现采这个信号，单拍脉冲是采不到的。
                // 原写法 S_FIN 里置 1、下一拍 S_IDLE 又清 0，等于 1 个 100MHz 周期的
                // 脉冲 —— 屏幕上那个"SCCB 自检"块会永远显示黄色（未完成），
                // 而实际上四次回读早就全部成功了。只在收到新的 start 时才清。
                if (start) begin
                    fin   <= 1'b0;
                    idx   <= 2'd0;
                    ok    <= 4'd0;
                    bad   <= 1'b0;
                    reg_a <= reg_of(2'd0);
                    st    <= S_ISSUE;
                end
            end

            S_ISSUE: begin
                reg_a <= reg_of(idx);
                go    <= 1'b1;              // 单拍脉冲，下一拍进入等待
                st    <= S_WAIT;
            end

            S_WAIT: begin
                if (done) begin
                    // 按索引锁存；ack_err 在本次事务开始时被清零，故此处是本次结果
                    case (idx)
                        2'd0: v_pidh <= rdat;
                        2'd1: v_pidl <= rdat;
                        2'd2: v_pad  <= rdat;
                        default: v_pwr <= rdat;
                    endcase
                    ok[idx] <= ~ack_err;
                    if (ack_err) bad <= 1'b1;

                    if (idx == 2'd3) begin
                        st <= S_FIN;
                    end else begin
                        idx  <= idx + 2'd1;
                        gapc <= 16'd0;
                        st   <= S_GAP;
                    end
                end
            end

            S_GAP: begin
                if (gapc == GAP_CYC) st <= S_ISSUE;
                else                 gapc <= gapc + 16'd1;
            end

            S_FIN: begin
                fin <= 1'b1;
                st  <= S_IDLE;
            end

            default: st <= S_IDLE;
            endcase
        end
    end

endmodule
