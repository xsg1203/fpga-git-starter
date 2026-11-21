//==========================================================================
// ov5640_cfg.v  —  OV5640 上电配置序列（DVP / RGB565 / 640x480 / 30fps）
//
// 【表项格式】24 位：{ADDR[15:0], DATA[7:0]}
//   OV5640 的寄存器地址是 16 位，SCCB 写为 4 字节
//   （DEV 0x78 + ADDR_H + ADDR_L + DATA），由 i2c_sccb.v 负责成帧。
//   旧版本曾把地址只留 8 位、把数据写进注释，导致配置从未真正生效，
//   这是 OV7670 的格式，务必不要再照抄。
//
// 【重要】本表为公开通用基线表。它不保证对你手上这颗模组 100% 生效
// （不同批次/不同窗口起点要求不同）。上板若不出图，按
// docs/03_上板调试记录.md 的步骤排查，最可能只需要改动以下 4 处：
//   0x3035/0x3036  PLL 分频倍频（决定 PCLK）
//   0x4300         输出格式字（RGB565 常见 0x6F / 0x61）
//   0x380C/0x380E  HTS/VTS（决定帧率）
//   0x3820/0x3821  镜像/翻转位
// 若你有厂商提供的完整初始化表，直接替换 cfg_rom 的 case 内容即可，
// 其余时序逻辑不用动。
//
// 特殊码：24'hFFFFFF = 序列结束；24'hFFFFFE = 纯延时 5ms
//==========================================================================
`timescale 1ns / 1ps

module ov5640_cfg (
    input  wire        clk,
    input  wire        rst_n,
    output reg         go,
    output reg  [15:0] o_reg,
    output reg  [7:0]  o_dat,
    input  wire        busy,
    input  wire        done,
    input  wire        ack_err,
    output reg         cfg_done,
    output reg  [7:0]  err_cnt      // SCCB 无 ACK 次数（应为 0）
);

    localparam [23:0] END_CODE = 24'hFFFFFF;
    localparam [23:0] DLY_CODE = 24'hFFFFFE;

    localparam [2:0] S_INIT = 3'd0,
                     S_GO   = 3'd1,
                     S_WAIT = 3'd2,
                     S_GAP  = 3'd3,
                     S_END  = 3'd4;

    reg [2:0]  st;
    reg [7:0]  idx;
    reg [18:0] gap;

    wire [23:0] ent = cfg_rom(idx);

    //----------------------------------------------------------------------
    // 寄存器表 {ADDR[15:0], DATA[7:0]}
    //----------------------------------------------------------------------
    function [23:0] cfg_rom;
        input [7:0] i;
        begin
            case (i)
            //----- 系统软复位与 PLL -----
            8'd0 : cfg_rom = {16'h3103, 8'h03};   // 时钟来自 pad（非 PLL）
            8'd1 : cfg_rom = {16'h3008, 8'h82};   // 软复位
            8'd2 : cfg_rom = DLY_CODE;            // 等 5ms
            8'd3 : cfg_rom = {16'h3008, 8'h42};   // 退出复位
            8'd4 : cfg_rom = {16'h3103, 8'h03};
            8'd5 : cfg_rom = {16'h3017, 8'hFF};   // pad 输出使能
            8'd6 : cfg_rom = {16'h3018, 8'hF0};   // pad 驱动能力
            8'd7 : cfg_rom = {16'h3034, 8'h1A};   // PLL 根分频=1
            8'd8 : cfg_rom = {16'h3037, 8'h13};   // PLL 预分频
            8'd9 : cfg_rom = {16'h3108, 8'h01};   // PCLK 根分频
            8'd10: cfg_rom = {16'h3035, 8'h21};   // PLL 控制
            8'd11: cfg_rom = {16'h3036, 8'hA1};   // PLL 倍频（按 24MHz 输入标定）
            8'd12: cfg_rom = {16'h3035, 8'h21};
            //----- SCCB / IO 驱动能力 -----
            8'd13: cfg_rom = {16'h3C01, 8'hB0};   // 先置复位位再打开
            8'd14: cfg_rom = {16'h3C02, 8'h02};
            8'd15: cfg_rom = {16'h3C03, 8'h02};
            8'd16: cfg_rom = {16'h3C04, 8'h02};
            8'd17: cfg_rom = {16'h3C05, 8'h02};
            8'd18: cfg_rom = {16'h3C06, 8'h00};
            8'd19: cfg_rom = {16'h3C07, 8'h07};   // 输出窗口控制
            8'd20: cfg_rom = {16'h3C08, 8'h07};
            8'd21: cfg_rom = {16'h3C09, 8'h07};
            8'd22: cfg_rom = {16'h3C0A, 8'h07};   // PCLK 极性等
            8'd23: cfg_rom = {16'h3C0B, 8'h07};
            8'd24: cfg_rom = {16'h3C0C, 8'h07};
            8'd25: cfg_rom = {16'h3C0D, 8'h07};
            //----- 自动曝光 / 自动白平衡（光照鲁棒性关键）-----
            8'd26: cfg_rom = {16'h3503, 8'h00};   // AEC/AGC 使能
            8'd27: cfg_rom = {16'h3406, 8'h00};   // AWB 自动
            //----- 输出窗口 640x480 -----
            8'd28: cfg_rom = {16'h3800, 8'h00};
            8'd29: cfg_rom = {16'h3801, 8'h00};
            8'd30: cfg_rom = {16'h3802, 8'h00};
            8'd31: cfg_rom = {16'h3803, 8'h04};
            8'd32: cfg_rom = {16'h3804, 8'h0A};   // X start 高
            8'd33: cfg_rom = {16'h3805, 8'hA3};   // X start 低
            8'd34: cfg_rom = {16'h3806, 8'h00};   // Y start 高
            8'd35: cfg_rom = {16'h3807, 8'h0A};   // Y start 低
            8'd36: cfg_rom = {16'h3808, 8'h02};   // H size = 640
            8'd37: cfg_rom = {16'h3809, 8'h80};
            8'd38: cfg_rom = {16'h380A, 8'h01};   // V size = 480
            8'd39: cfg_rom = {16'h380B, 8'hE0};
            8'd40: cfg_rom = {16'h380C, 8'h07};   // HTS = 1896
            8'd41: cfg_rom = {16'h380D, 8'h68};
            8'd42: cfg_rom = {16'h380E, 8'h02};   // VTS = 632
            8'd43: cfg_rom = {16'h380F, 8'h78};
            8'd44: cfg_rom = {16'h3810, 8'h03};   // ISP X offset
            8'd45: cfg_rom = {16'h3811, 8'h01};
            8'd46: cfg_rom = {16'h3812, 8'h03};   // ISP Y offset
            8'd47: cfg_rom = {16'h3813, 8'h01};
            8'd48: cfg_rom = {16'h3814, 8'h31};   // 不做子采样
            8'd49: cfg_rom = {16'h3815, 8'h31};
            8'd50: cfg_rom = {16'h3816, 8'h01};
            8'd51: cfg_rom = {16'h3817, 8'h01};
            8'd52: cfg_rom = {16'h3820, 8'h46};   // 镜像/翻转
            8'd53: cfg_rom = {16'h3821, 8'h46};
            8'd54: cfg_rom = {16'h3822, 8'h01};
            8'd55: cfg_rom = {16'h3823, 8'h02};
            8'd56: cfg_rom = {16'h3824, 8'h01};
            8'd57: cfg_rom = {16'h3825, 8'h02};
            8'd58: cfg_rom = {16'h3826, 8'h01};
            8'd59: cfg_rom = {16'h3827, 8'h02};
            //----- 输出格式 RGB565 -----
            8'd60: cfg_rom = {16'h4300, 8'h6F};   // RGB565（备选 0x61）
            8'd61: cfg_rom = {16'h501F, 8'h01};   // ISP 输出 RGB
            8'd62: cfg_rom = {16'h5000, 8'hA7};   // LENC/BPC/WPC/CIP
            8'd63: cfg_rom = {16'h503D, 8'h00};   // 测试图案（改 0x82 = 彩条自检）
            8'd64: cfg_rom = {16'h3008, 8'h02};   // 开始输出图像
            8'd65: cfg_rom = END_CODE;
            default: cfg_rom = END_CODE;
            endcase
        end
    endfunction

    //----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st       <= S_INIT;
            idx      <= 8'd0;
            go       <= 1'b0;
            gap      <= 19'd0;
            o_reg    <= 16'd0;
            o_dat    <= 8'd0;
            cfg_done <= 1'b0;
            err_cnt  <= 8'd0;
        end else begin
            go <= 1'b0;
            case (st)
                S_INIT: begin
                    if (ent == END_CODE) begin
                        cfg_done <= 1'b1;
                        st       <= S_END;
                    end else if (ent == DLY_CODE) begin
                        gap <= 19'd250000;          // 5ms @50MHz
                        st  <= S_GAP;
                    end else begin
                        o_reg <= ent[23:8];
                        o_dat <= ent[7:0];
                        st    <= S_GO;
                    end
                end
                S_GO: begin
                    go <= 1'b1;
                    st <= S_WAIT;
                end
                S_WAIT: begin
                    if (done) begin
                        if (ack_err) err_cnt <= err_cnt + 8'd1;
                        gap <= 19'd2000;            // 40us 字节间隔
                        st  <= S_GAP;
                    end
                end
                S_GAP: begin
                    if (gap == 19'd0) begin
                        idx <= idx + 8'd1;
                        st  <= S_INIT;
                    end else begin
                        gap <= gap - 19'd1;
                    end
                end
                S_END: st <= S_END;
                default: st <= S_INIT;
            endcase
        end
    end

endmodule
