# 一键跑完整实现流程（综合 -> 实现 -> bitstream），并输出可复核的报告
#
#   vivado -mode batch -source scripts/build_all.tcl
#
# 报告输出到 build/reports/（build/ 已被 .gitignore 忽略，属可重建产物）
#
# 注意：Vivado 2017.4 在 Windows 批处理下按非 UTF-8 解析 Tcl 输出，
# 所有 puts 一律用纯 ASCII，否则日志乱码。

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set proj_file  [file join $root_dir build ct_ebaz4205.xpr]
set rpt_dir    [file join $root_dir build reports]

if {![file exists $proj_file]} {
    error "Project not found: $proj_file  -- run scripts/create_project.tcl first"
}
file mkdir $rpt_dir

open_project $proj_file
puts "==== PROJECT: $proj_file ===="

# ---------------- Synthesis ----------------
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "==== SYNTH FAILED ===="
    puts "STATUS: [get_property STATUS [get_runs synth_1]]"
    error "synthesis failed"
}
puts "==== SYNTH OK: [get_property STATUS [get_runs synth_1]] ===="

open_run synth_1 -name synth_1
report_utilization       -file [file join $rpt_dir util_synth.rpt]
report_timing_summary    -file [file join $rpt_dir timing_synth.rpt] -max_paths 5
close_design

# ---------------- Implementation + bitstream ----------------
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "==== IMPL FAILED ===="
    puts "STATUS: [get_property STATUS [get_runs impl_1]]"
    error "implementation failed"
}
puts "==== IMPL OK: [get_property STATUS [get_runs impl_1]] ===="

open_run impl_1
report_timing_summary   -file [file join $rpt_dir timing_impl.rpt] -max_paths 10 -warn_on_violation
report_utilization      -file [file join $rpt_dir util_impl.rpt]
report_clock_interaction -file [file join $rpt_dir clock_interaction.rpt]
report_drc              -file [file join $rpt_dir drc.rpt]
report_io               -file [file join $rpt_dir io.rpt]

# ---------------- Checks ----------------
# 1) 未分配引脚的端口（下载后不会有任何信号，必须为 0）
set unb {}
foreach p [get_ports] {
    if {[get_property PACKAGE_PIN [get_ports $p]] == ""} { lappend unb $p }
}
puts "==== UNCONSTRAINED_PORTS: [llength $unb] $unb ===="

# 2) 时序关键指标
set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
puts "==== WNS: $wns ns ===="
puts "==== WHS: $whs ns ===="

# 3) 位流文件
set bit [glob -nocomplain [file join $root_dir build ct_ebaz4205.runs impl_1 *.bit]]
if {[llength $bit] > 0} {
    puts "==== BITSTREAM: [lindex $bit 0] ([file size [lindex $bit 0]] bytes) ===="
} else {
    puts "==== BITSTREAM: NOT FOUND ===="
}

puts "==== BUILD DONE ===="
