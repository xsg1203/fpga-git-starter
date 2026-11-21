//==========================================================================
// i2c_sccb.v  —  SCCB(类 I2C) 主机，**四字节写**：
//                DEV(0x78) + REG[15:8] + REG[7:0] + DATA
//
// 为什么是四字节：OV5640 的寄存器地址是 16 位（0x3008/0x3808…），
// SCCB 写传输必须把地址拆成高/低两个字节，所以一帧共 4 字节。
// 三字节（DEV+REG+DATA）是 OV7670/OV7725 这类 8 位地址器件的格式，
// 用在 OV5640 上会形成一个"只有地址没有数据"的畸形传输：传感器对前三个
// 字节照样回 ACK（所以 ACK 错误检测看不出来），但寄存器根本没有被写入。
//
// 位槽：4 字节 x 8 bit = 32 个数据槽，加 4 个 ACK 槽 = 共 36 槽。
//       ACK 槽位于 slot 8 / 17 / 26 / 35。
//
// 时序：DIV = 每个 1/4 SCL 周期的 clk 拍数；50MHz/DIV=64 -> SCL 约 195kHz
// 开漏输出：调用方将 scl_lo/sda_lo 接到 1'bz 上（模块板已有 4.7K 上拉）
//==========================================================================
`timescale 1ns / 1ps

module i2c_sccb #(
    parameter [7:0] DIV = 8'd64
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        go,          // 单拍启动
    input  wire [7:0]  dev_a,       // 0x78
    input  wire [15:0] reg_a,       // 16 位寄存器地址
    input  wire [7:0]  wdat,
    output reg         scl_lo,      // 1 = 拉低 SCL
    output reg         sda_lo,      // 1 = 拉低 SDA
    input  wire        sda_i,       // SDA 回读
    output reg         busy,
    output reg         ack_err,     // 从机未拉低 ACK
    output reg         done         // 单拍完成脉冲
);

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    localparam [5:0] LAST_SLOT = 6'd35;   // 4 字节 + 4 ACK 槽的最后一槽

    reg [7:0]  divc;
    reg [1:0]  st;
    reg [1:0]  ph;
    reg [5:0]  slot;
    reg [31:0] sr;

    wire qt       = (divc == (DIV - 8'd1));
    wire ack_slot = (slot == 6'd8) || (slot == 6'd17) ||
                    (slot == 6'd26) || (slot == 6'd35);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)       divc <= 8'd0;
        else if (qt)      divc <= 8'd0;
        else              divc <= divc + 8'd1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st      <= S_IDLE;
            ph      <= 2'd0;
            slot    <= 6'd0;
            sr      <= 32'd0;
            scl_lo  <= 1'b0;
            sda_lo  <= 1'b0;
            busy    <= 1'b0;
            ack_err <= 1'b0;
            done    <= 1'b0;
        end else begin
            done <= 1'b0;

            if (st == S_IDLE) begin
                scl_lo <= 1'b0;
                sda_lo <= 1'b0;
                busy   <= 1'b0;
                if (go) begin
                    // 发送顺序：DEV, ADDR_H, ADDR_L, DATA（sr[31] 为最先发出的一位）
                    sr      <= {dev_a, reg_a[15:8], reg_a[7:0], wdat};
                    slot    <= 6'd0;
                    ph      <= 2'd0;
                    ack_err <= 1'b0;
                    busy    <= 1'b1;
                    st      <= S_START;
                end
            end else if (qt) begin
                case (st)
                //---------- START: SCL 高时 SDA 下降 ----------
                S_START: begin
                    case (ph)
                        2'd0: begin scl_lo <= 1'b0; sda_lo <= 1'b0; end
                        2'd1: begin scl_lo <= 1'b0; sda_lo <= 1'b1; end
                        2'd2: begin scl_lo <= 1'b1; sda_lo <= 1'b1; end
                        2'd3: begin st <= S_DATA;   ph   <= 2'd0; end
                    endcase
                    if (ph != 2'd3) ph <= ph + 2'd1;
                end
                //---------- 36 个位槽，每槽 4 个 1/4 周期 ----------
                S_DATA: begin
                    case (ph)
                        2'd0: scl_lo <= 1'b1;                       // SCL 拉低，数据保持
                        2'd1: begin                                 // SCL 低期间更新数据
                            scl_lo <= 1'b1;
                            sda_lo <= ack_slot ? 1'b0 : ~sr[31];
                        end
                        2'd2: scl_lo <= 1'b0;                       // 释放 SCL -> 高
                        2'd3: begin
                            scl_lo <= 1'b0;
                            if (ack_slot && sda_i) ack_err <= 1'b1; // ACK 采样
                            // ACK 槽不消耗数据位：只有数据槽才移位。
                            // 若在 ACK 槽也移位，每过一个字节就会多移一位，
                            // 表现为"第一个字节正确、后面全部左移一格"。
                            if (!ack_slot) sr <= {sr[30:0], 1'b0};
                            if (slot == LAST_SLOT) begin
                                st <= S_STOP; ph <= 2'd0;
                            end else begin
                                slot <= slot + 6'd1; ph <= 2'd0;
                            end
                        end
                    endcase
                    if (ph != 2'd3) ph <= ph + 2'd1;
                end
                //---------- STOP: SCL 高时 SDA 上升 ----------
                S_STOP: begin
                    case (ph)
                        2'd0: begin scl_lo <= 1'b1; sda_lo <= 1'b1; end
                        2'd1: begin scl_lo <= 1'b0; sda_lo <= 1'b1; end
                        2'd2: begin scl_lo <= 1'b0; sda_lo <= 1'b0; end
                        2'd3: begin st <= S_IDLE; busy <= 1'b0; done <= 1'b1; end
                    endcase
                    if (ph != 2'd3) ph <= ph + 2'd1;
                end

                default: st <= S_IDLE;
                endcase
            end
        end
    end

endmodule
