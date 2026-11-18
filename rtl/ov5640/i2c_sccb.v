//==========================================================================
// i2c_sccb.v  —  SCCB(类 I2C) 主机，三字节写：DEV(0x78) + REG + DATA
// DIV = 每个 1/4 SCL 周期的 clk 拍数；50MHz/DIV=64 -> SCL 约 195kHz
// 开漏输出：调用方将 scl_lo/sda_lo 接到 1'bz 上（模块板已有 4.7K 上拉）
//==========================================================================
`timescale 1ns / 1ps

module i2c_sccb #(
    parameter [7:0] DIV = 8'd64
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       go,          // 单拍启动
    input  wire [7:0] dev_a,       // 0x78
    input  wire [7:0] reg_a,
    input  wire [7:0] wdat,
    output reg        scl_lo,      // 1 = 拉低 SCL
    output reg        sda_lo,      // 1 = 拉低 SDA
    input  wire       sda_i,       // SDA 回读
    output reg        busy,
    output reg        ack_err,     // 从机未拉低 ACK
    output reg        done         // 单拍完成脉冲
);

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [7:0]  divc;
    reg [1:0]  st;
    reg [1:0]  ph;
    reg [4:0]  slot;               // 0..26 = 3 字节 + 3 个 ACK 槽
    reg [23:0] sr;

    wire qt       = (divc == (DIV - 8'd1));
    wire ack_slot = (slot == 5'd8) || (slot == 5'd17) || (slot == 5'd26);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)       divc <= 8'd0;
        else if (qt)      divc <= 8'd0;
        else              divc <= divc + 8'd1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st      <= S_IDLE;
            ph      <= 2'd0;
            slot    <= 5'd0;
            sr      <= 24'd0;
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
                    sr      <= {dev_a, reg_a, wdat};
                    slot    <= 5'd0;
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
                //---------- 27 个位槽，每槽 4 个 1/4 周期 ----------
                S_DATA: begin
                    case (ph)
                        2'd0: scl_lo <= 1'b1;                       // SCL 拉低，数据保持
                        2'd1: begin                                 // SCL 低期间更新数据
                            scl_lo <= 1'b1;
                            sda_lo <= ack_slot ? 1'b0 : ~sr[23];
                        end
                        2'd2: scl_lo <= 1'b0;                       // 释放 SCL -> 高
                        2'd3: begin
                            scl_lo <= 1'b0;
                            if (ack_slot && sda_i) ack_err <= 1'b1; // ACK 采样
                            sr <= {sr[22:0], 1'b0};
                            if (slot == 5'd26) begin
                                st <= S_STOP; ph <= 2'd0;
                            end else begin
                                slot <= slot + 5'd1; ph <= 2'd0;
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
