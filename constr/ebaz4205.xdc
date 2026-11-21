#===========================================================================
# ebaz4205.xdc  —  EBAZ4205 核心板 + 教学扩展板 V1.1
# Part: xc7z010clg400-1   Vivado 2017.4
# 引脚依据：EBAZ4205_硬件说明.md（核心板 4205.pdf / 扩展板 EXBOARD V1.1）
#
# 注意：
#  1) P20 标称 VGA_R4，与部分功能复用，本设计固定作 VGA 用
#  2) A20 = ov_rst_n，与"PL-UART RX"复用，本设计不使能 PL UART
#  3) ov_pclk(E19) 为非专用时钟引脚，必须加 CLOCK_DEDICATED_ROUTE FALSE
#===========================================================================

#---------------------------------------------------------------------------
# 器件配置
#---------------------------------------------------------------------------
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

#---------------------------------------------------------------------------
# 主时钟 50MHz（X5 已焊，接 N18）
#---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVCMOS33} [get_ports clk50]
create_clock -period 20.000 -name clk50 [get_ports clk50]

#---------------------------------------------------------------------------
# 按键 KEY1~KEY4（10K 上拉，低有效）
#---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN G19 IOSTANDARD LVCMOS33} [get_ports {key_n[0]}]
set_property -dict {PACKAGE_PIN J19 IOSTANDARD LVCMOS33} [get_ports {key_n[1]}]
set_property -dict {PACKAGE_PIN K19 IOSTANDARD LVCMOS33} [get_ports {key_n[2]}]
set_property -dict {PACKAGE_PIN L16 IOSTANDARD LVCMOS33} [get_ports {key_n[3]}]

#---------------------------------------------------------------------------
# LED0~LED3（低电平点亮，2K 限流）
#---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN H20 IOSTANDARD LVCMOS33} [get_ports {led_n[0]}]
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports {led_n[1]}]
set_property -dict {PACKAGE_PIN J20 IOSTANDARD LVCMOS33} [get_ports {led_n[2]}]
set_property -dict {PACKAGE_PIN L19 IOSTANDARD LVCMOS33} [get_ports {led_n[3]}]

#---------------------------------------------------------------------------
# OV5640（DVP 8bit）
#---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN B20 IOSTANDARD LVCMOS33} [get_ports {ov_data[0]}]
set_property -dict {PACKAGE_PIN B19 IOSTANDARD LVCMOS33} [get_ports {ov_data[1]}]
set_property -dict {PACKAGE_PIN C20 IOSTANDARD LVCMOS33} [get_ports {ov_data[2]}]
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {ov_data[3]}]
set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33} [get_ports {ov_data[4]}]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS33} [get_ports {ov_data[5]}]
set_property -dict {PACKAGE_PIN H18 IOSTANDARD LVCMOS33} [get_ports {ov_data[6]}]
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports {ov_data[7]}]
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports ov_pclk]
set_property -dict {PACKAGE_PIN F19 IOSTANDARD LVCMOS33} [get_ports ov_href]
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports ov_vsync]
set_property -dict {PACKAGE_PIN F20 IOSTANDARD LVCMOS33} [get_ports ov_xclk]
set_property -dict {PACKAGE_PIN A20 IOSTANDARD LVCMOS33} [get_ports ov_rst_n]
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports ov_pwdn]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD LVCMOS33} [get_ports ov_scl]
set_property -dict {PACKAGE_PIN G20 IOSTANDARD LVCMOS33} [get_ports ov_sda]

# 像素时钟来自摄像头，走的是普通 IO（E19），必须关闭专用时钟布线检查。
#
# 【周期取值说明】不是拍脑袋的 40ns。OV5640 在 0x3035=0x21 / 0x3036=0x69 / XCLK 24MHz
# 下，PCLK 由 HTS x VTS x 帧率推出：1896 x 984 x 30fps ≈ 56MHz（周期 17.86ns）。
# 若仍按 25MHz(40ns) 约束，工具会以为有 40ns 余量，实际只有 17.86ns ——
#   采集寄存器一旦在真实硅片上违例，画面就是"黑屏/错位"，而报告却是全绿。
# 这里按 50MHz(20ns) 约束：留 12% 余量便于布通，同时让 WNS 具备参考意义。
create_clock -period 20.000 -name ov_pclk [get_ports ov_pclk]

# CLOCK_DEDICATED_ROUTE 必须落在真实存在的 net 上。
# 注意两点：
#  1) XDC 不支持 if/foreach 等控制流（会报 Designutils 20-1307 并让整份约束失效），
#     所以这里只能用两条独立命令，不能做条件判断。
#  2) 综合阶段 IBUF 尚未生成，第一条命令会报
#     CRITICAL WARNING 'set_property' expects at least one object —— 这是"预期噪声"：
#     该属性在 opt/place 阶段才会真正落到 ov_pclk_IBUF 上，place 不报 30-574 错误即证明生效。
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -quiet ov_pclk_IBUF]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -quiet ov_pclk]

# DVP 数据相对 PCLK 的输入延迟：OV5640 手册 t_PCLK->data 典型 5ns、最大 8ns。
# 原先给 10ns 在 20ns 周期下几乎吃掉一半预算，属于无效约束；
# 改为 8/1 后才能真正评估采集寄存器能否在 56MHz 下稳定采样。
set_input_delay -clock ov_pclk -max 8.000 [get_ports {ov_data[*] ov_href ov_vsync}]
set_input_delay -clock ov_pclk -min 1.000 [get_ports {ov_data[*] ov_href ov_vsync}]

#---------------------------------------------------------------------------
# VGA（电阻网络 DAC，RGB565）
#---------------------------------------------------------------------------
# R[4:0] = vga_data[15:11]
set_property -dict {PACKAGE_PIN P20 IOSTANDARD LVCMOS33} [get_ports {vga_data[15]}]
set_property -dict {PACKAGE_PIN M17 IOSTANDARD LVCMOS33} [get_ports {vga_data[14]}]
set_property -dict {PACKAGE_PIN N20 IOSTANDARD LVCMOS33} [get_ports {vga_data[13]}]
set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33} [get_ports {vga_data[12]}]
set_property -dict {PACKAGE_PIN M18 IOSTANDARD LVCMOS33} [get_ports {vga_data[11]}]
# G[5:0] = vga_data[10:5]
set_property -dict {PACKAGE_PIN L17 IOSTANDARD LVCMOS33} [get_ports {vga_data[10]}]
set_property -dict {PACKAGE_PIN L20 IOSTANDARD LVCMOS33} [get_ports {vga_data[9]}]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {vga_data[8]}]
set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS33} [get_ports {vga_data[7]}]
set_property -dict {PACKAGE_PIN T20 IOSTANDARD LVCMOS33} [get_ports {vga_data[6]}]
set_property -dict {PACKAGE_PIN R19 IOSTANDARD LVCMOS33} [get_ports {vga_data[5]}]
# B[4:0] = vga_data[4:0]
set_property -dict {PACKAGE_PIN P19 IOSTANDARD LVCMOS33} [get_ports {vga_data[4]}]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33} [get_ports {vga_data[3]}]
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports {vga_data[2]}]
set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS33} [get_ports {vga_data[1]}]
set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33} [get_ports {vga_data[0]}]

set_property -dict {PACKAGE_PIN U20 IOSTANDARD LVCMOS33} [get_ports vga_hsync]
set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVCMOS33} [get_ports vga_vsync]

# 纯组合驱动到引脚，无外部采样时钟，输出侧不建时序关系。
# 注意：clk_pix 由 MMCM 自动派生，时钟对象名不是 "clk_pix"（实际是 clk_pix_raw），
# 原来写 [get_clocks clk_pix] 会报 No valid object(s) 并静默失效，这条约束等于没写。
# 改为从 MMCM 输出引脚反查时钟对象，不依赖自动命名的具体字符串。
# XDC 不支持 if 控制流，故直接写单条命令。
set_false_path -from [get_clocks -of_objects [get_pins u_clk/u_mmcm/CLKOUT1]] \
               -to   [get_ports {vga_data[*] vga_hsync vga_vsync}]
set_false_path -from [get_ports {key_n[*]}]
set_false_path -to   [get_ports {led_n[*] ov_xclk ov_rst_n ov_pwdn}]

#---------------------------------------------------------------------------
# 位流
#---------------------------------------------------------------------------
set_property BITSTREAM.GENERAL.COMPRESS TRUE       [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLNONE   [current_design]
