//==========================================================================
// sccb_rd.v  —  SCCB 单寄存器读（OV5640 "两阶段" 读时序）
//
// 为什么需要读：前三轮改动（SCCB 字节格式、输出窗口、AEC、PAD 方向）
// 上板后现象完全没有变化，这本身就是一个强线索 —— 寄存器很可能一条都没写进去。
// 写操作无法自证（从机对每个字节都回 ACK，写错也看不出来），
// 唯一能自证的是"读回一个已知常量"：OV5640 的 PID 固定为 0x5640。
//
// 时序（OmniVision SCCB 规范）：
//   1) START + DEV_W(0x78) + ADDR_H + ADDR_L  + 每字节一个 ACK  -> STOP
//   2) START + DEV_R(0x79) + ACK               -> 读 8 bit
//   3) 主机在第 9 个时钟发 NACK（释放 SDA）     -> STOP
//
// 位槽结构与 i2c_sccb.v 完全一致（4 个 1/4 周期 = 1 个位槽），
// 这样两条路径的电气时序一致，不会出现"写能过、读不能过"的怪现象。
//
// DIV=128 且 clk=50MHz -> SCL 约 97.6kHz（偏保守）。
// 之所以放慢：多数教学扩展板没有 I2C 上拉，靠 FPGA 内部弱上拉（约 20kΩ），
// 上升沿较慢，100kHz 比 200kHz 稳得多。
//==========================================================================
`timescale 1ns / 1ps

module sccb_rd #(
    parameter [7:0] DIV = 8'd128
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        go,          // 单拍启动
    input  wire [7:0]  dev_a,       // 0x78
    input  wire [15:0] reg_a,
    output reg         scl_lo,
    output reg         sda_lo,
    input  wire        sda_i,
    output reg         busy,
    output reg         ack_err,     // 本次事务中出现过 NACK
    output reg  [7:0]  rdat,
    output reg         done         // 单拍完成
);

    localparam [2:0] S_IDLE = 3'd0,
                     S_ST   = 3'd1,   // START
                     S_TXA  = 3'd2,   // 发 0x78 + ADDR_H + ADDR_L（27 槽）
                     S_SP1  = 3'd3,   // STOP
                     S_ST2  = 3'd4,   // 第二个 START
                     S_TXI  = 3'd5,   // 发 0x79（9 槽）
                     S_RX   = 3'd6,   // 读 8 bit + NACK（9 槽）
                     S_SP2  = 3'd7;   // STOP

    reg [7:0]  divc;
    reg [2:0]  st;
    reg [1:0]  ph;
    reg [5:0]  slot;
    reg [23:0] sr;
    reg [7:0]  rsh;

    wire qt = (divc == (DIV - 8'd1));

    // 字节边界的 ACK 槽
    wire ack_a = (slot == 6'd8) || (slot == 6'd17) || (slot == 6'd26);
    wire ack_i = (slot == 6'd8);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) divc <= 8'd0;
        else if (qt) divc <= 8'd0;
        else         divc <= divc + 8'd1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st      <= S_IDLE;
            ph      <= 2'd0;
            slot    <= 6'd0;
            sr      <= 24'd0;
            rsh     <= 8'd0;
            scl_lo  <= 1'b0;
            sda_lo  <= 1'b0;
            busy    <= 1'b0;
            ack_err <= 1'b0;
            rdat    <= 8'd0;
            done    <= 1'b0;
        end else begin
            done <= 1'b0;

            if (st == S_IDLE) begin
                scl_lo <= 1'b0;
                sda_lo <= 1'b0;
                busy   <= 1'b0;
                if (go) begin
                    sr      <= {dev_a, reg_a[15:8], reg_a[7:0]};
                    slot    <= 6'd0;
                    ph      <= 2'd0;
                    ack_err <= 1'b0;
                    busy    <= 1'b1;
                    st      <= S_ST;
                end
            end else if (qt) begin
                case (st)
                //--------------- 第一个 START ----------------
                S_ST: begin
                    case (ph)
                        2'd0: begin scl_lo <= 1'b0; sda_lo <= 1'b0; end
                        2'd1: begin scl_lo <= 1'b0; sda_lo <= 1'b1; end
                        2'd2: begin scl_lo <= 1'b1; sda_lo <= 1'b1; end
                        2'd3: begin st <= S_TXA; ph <= 2'd0; end
                    endcase
                    if (ph != 2'd3) ph <= ph + 2'd1;
                end
                //--------------- 三个字节 + 三个 ACK 槽 ----------------
                S_TXA: begin
                    case (ph)
                        2'd0: scl_lo <= 1'b1;
                        2'd1: begin
                            scl_lo <= 1'b1;
                            sda_lo <= ack_a ? 1'b0 : ~sr[23];
                        end
                        2'd2: scl_lo <= 1'b0;
                        2'd3: begin
                            scl_lo <= 1'b0;
                            if (ack_a && sda_i) ack_err <= 1'b1;
                            if (!ack_a) sr <= {sr[22:0], 1'b0};
                            if (slot == 6'd26) begin
                                st <= S_SP1; ph <= 2'd0;
                            end else begin
                                slot <= slot + 6'd1; ph <= 2'd0;
                            end
                        end
                    endcase
                    if (ph != 2'd3) ph <= ph + 2'd1;
                end
                //--------------- STOP ----------------
                S_SP1: begin
                    case (ph)
                        2'd0: begin scl_lo <= 1'b1; sda_lo <= 1'b1; end
                        2'd1: begin scl_lo <= 1'b0; sda_lo <= 1'b1; end
                        2'd2: begin scl_lo <= 1'b0; sda_lo <= 1'b0; end
                        2'd3: begin
                            // 第二个 START：重新装载 0x79，槽位归零
                            sr   <= {dev_a | 8'h01, 16'd0};
                            slot <= 6'd0;
                            st   <= S_ST2;
                            ph   <= 2'd0;
                        end
                    endcase
                    if (ph != 2'd3) ph <= ph + 2'd1;
                end
                //--------------- 第二个 START ----------------
                S_ST2: begin
                    case (ph)
                        2'd0: begin scl_lo <= 1'b0; sda_lo <= 1'b0; end
                        2'd1: begin scl_lo <= 1'b0; sda_lo <= 1'b1; end
                        2'd2: begin scl_lo <= 1'b1; sda_lo <= 1'b1; end
                        2'd3: begin st <= S_TXI; ph <= 2'd0; end
                    endcase
                    if (ph != 2'd3) ph <= ph + 2'd1;
                end
                //--------------- 读地址字节 0x79 ----------------
                S_TXI: begin
                    case (ph)
                        2'd0: scl_lo <= 1'b1;
                        2'd1: begin
                            scl_lo <= 1'b1;
                            sda_lo <= ack_i ? 1'b0 : ~sr[23];
                        end
                        2'd2: scl_lo <= 1'b0;
                        2'd3: begin
                            scl_lo <= 1'b0;
                            if (ack_i && sda_i) ack_err <= 1'b1;
                            if (!ack_i) sr <= {sr[22:0], 1'b0};
                            if (ack_i) begin
                                // 必须清零槽位：否则 S_RX 一进来 slot 仍是 8，
                                // 首个相位的 ph3 就判定"读完了"，rdat 直接锁存初值 0。
                                st   <= S_RX;
                                slot <= 6'd0;
                                ph   <= 2'd0;
                            end else begin
                                slot <= slot + 6'd1; ph <= 2'd0;
                            end
                        end
                    endcase
                    if (ph != 2'd3) ph <= ph + 2'd1;
                end
                //--------------- 读 8 bit + NACK ----------------
                // 主机全程释放 SDA；第 9 槽保持释放即为 NACK。
                S_RX: begin
                    case (ph)
                        2'd0: begin scl_lo <= 1'b1; sda_lo <= 1'b0; end
                        2'd1: begin scl_lo <= 1'b1; sda_lo <= 1'b0; end
                        2'd2: scl_lo <= 1'b0;                       // SCL 上升，从机数据已稳定
                        2'd3: begin
                            scl_lo <= 1'b0;
                            if (slot < 6'd8) begin
                                rsh <= {rsh[6:0], sda_i};
                                slot <= slot + 6'd1;
                                ph   <= 2'd0;
                            end else begin
                                rdat <= rsh;                        // 8 bit 已全部移入
                                st   <= S_SP2;
                                ph   <= 2'd0;
                            end
                        end
                    endcase
                    if (ph != 2'd3) ph <= ph + 2'd1;
                end
                //--------------- STOP -> 结束 ----------------
                S_SP2: begin
                    case (ph)
                        2'd0: begin scl_lo <= 1'b1; sda_lo <= 1'b1; end
                        2'd1: begin scl_lo <= 1'b0; sda_lo <= 1'b1; end
                        2'd2: begin scl_lo <= 1'b0; sda_lo <= 1'b0; end
                        2'd3: begin
                            st   <= S_IDLE;
                            busy <= 1'b0;
                            done <= 1'b1;
                        end
                    endcase
                    if (ph != 2'd3) ph <= ph + 2'd1;
                end

                default: st <= S_IDLE;
                endcase
            end
        end
    end

endmodule
