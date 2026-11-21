# 无头全流程构建（不依赖 .xpr 工程，直接 源码 -> 综合 -> 实现 -> bit）
#
#   vivado -mode batch -source scripts/build_flat.tcl
#
# 为什么单独有这个脚本：
#   Vivado 工程的 run 状态（synth_1/impl_1 的中间产物）有时会被一次失败的
#   运行污染，表现为 impl 阶段报 "The design is empty"，此时工程本身看似正常
#   （源文件、约束、父子 run 都对），但无论怎么 reset_run 都跑不过去。
#   本脚本绕过工程，确定性最高，适合做"这份 RTL+XDC 到底行不行"的判定，
#   也可用于 CI。
#
# 产物输出到 build_flat/（已被 .gitignore 忽略）
#
# 注意：Vivado 2017.4 批处理下 Tcl 按非 UTF-8 解析 puts，日志一律用纯 ASCII。

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set out_dir    [file join $root_dir build_flat]
file mkdir $out_dir

# ---- 读源码：递归收集 rtl/ 下所有 .v ----
# 递归而非固定两层：深层目录被漏掉时，症状是 "module 'xxx' not found"，
# 与真正的代码错误混在一起很难区分。清单照例打印出来。
proc ct_collect_v {dir} {
    set out {}
    foreach f [glob -nocomplain -directory $dir -types f *.v] {
        lappend out [file normalize $f]
    }
    foreach d [glob -nocomplain -directory $dir -types d *] {
        set out [concat $out [ct_collect_v $d]]
    }
    return $out
}

set rtl_files [ct_collect_v [file join $root_dir rtl]]
puts "==== RTL files: [llength $rtl_files] ===="
foreach f $rtl_files {
    puts "  [string range $f [expr {[string length $root_dir] + 1}] end]"
}
read_verilog $rtl_files

# ---- 读约束（综合前读，opt/place 阶段自动生效）----
read_xdc [file join $root_dir constr ebaz4205.xdc]

# ---- 综合 ----
synth_design -top ct_top -part xc7z010clg400-1
write_checkpoint -force [file join $out_dir post_synth.dcp]
report_utilization -file [file join $out_dir util_synth.rpt]

# ---- 实现 ----
opt_design
place_design
route_design

report_timing_summary -file [file join $out_dir timing_impl.rpt] -max_paths 10 -warn_on_violation
report_utilization    -file [file join $out_dir util_impl.rpt]
report_drc            -file [file join $out_dir drc.rpt]
report_io             -file [file join $out_dir io.rpt]

# ---- 位流 ----
write_bitstream -force [file join $out_dir ct_top.bit]

# ---- 汇总判据 ----
set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
puts "==== PORTS: [llength [get_ports]] ===="
puts "==== CELLS: [llength [get_cells -hier]] ===="
puts "==== WNS: $wns ns ===="
puts "==== WHS: $whs ns ===="
puts "==== BITSTREAM: [file join $out_dir ct_top.bit] ([file size [file join $out_dir ct_top.bit]] bytes) ===="
puts "==== FLAT BUILD DONE ===="
