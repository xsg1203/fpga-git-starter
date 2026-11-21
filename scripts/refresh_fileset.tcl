# 刷新已打开工程的源文件列表
#
# 用途：新增/删除 RTL 文件后，让当前 .xpr 的 fileset 与磁盘一致。
#
# 为什么需要它：
#   .xpr 里的文件列表是建工程那一刻"拍快照"的结果，之后往 rtl/ 里加模块，
#   .xpr 不会自动知道。此时 build_flat.tcl（直接读源码）能跑通，
#   但 GUI 里点综合会报
#       ERROR: [Synth 8-439] module 'xxx' not found
#   这个错误很容易被误读成"代码写错了"，实际只是文件没登记。
#
# 两种用法：
#   1) GUI 里已经打开了工程（推荐，不用关 Vivado）
#      在 Tcl Console 执行：
#        source {D:/fpga/color_track_ebaz4205/scripts/refresh_fileset.tcl}
#   2) 批处理：
#        vivado -mode batch -source scripts/refresh_fileset.tcl
#
# 注意：批处理方式要求 GUI 没有打开同一个工程（会报目录被占用）。
# 输出一律纯 ASCII，原因见 create_project.tcl 顶部说明。

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set proj_file  [file join $root_dir build ct_ebaz4205.xpr]

# 递归收集某一目录下所有 .v（原脚本只 glob 一层，深一层就会静默漏掉）
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

# GUI 已打开工程时 current_project 有效；批处理下需要显式打开
set cur ""
catch { set cur [current_project -quiet] }
if {$cur eq ""} {
    open_project $proj_file
}
puts "==== Project: [get_property DIRECTORY [current_project]] ===="

# 现有已登记文件（规范化后比较，避免路径分隔符差异导致重复添加）
set have {}
foreach f [get_files -quiet] {
    if {[string match -nocase *.v $f]} {
        lappend have [file normalize $f]
    }
}

set all   [ct_collect_v [file join $root_dir rtl]]
set added 0
puts "==== RTL on disk: [llength $all] ===="
foreach f $all {
    if {[lsearch -exact $have $f] < 0} {
        add_files -norecurse -fileset sources_1 $f
        puts "  + added [string range $f [expr {[string length $root_dir] + 1}] end]"
        incr added
    }
}

# 约束同样按需补
set xdc [file normalize [file join $root_dir constr ebaz4205.xdc]]
set have_xdc {}
foreach f [get_files -quiet] {
    if {[string match -nocase *.xdc $f]} {
        lappend have_xdc [file normalize $f]
    }
}
if {[lsearch -exact $have_xdc $xdc] < 0} {
    add_files -fileset constrs_1 -norecurse $xdc
    puts "  + added constr/ebaz4205.xdc"
}

set_property top ct_top [get_filesets sources_1]
update_compile_order -fileset sources_1

# 文件列表变了就必须重跑综合，否则综合用的是旧网表
foreach r {synth_1 impl_1} {
    if {[llength [get_runs -quiet $r]] > 0} {
        reset_run $r
        puts "  reset run $r"
    }
}

set total 0
foreach f [get_files -quiet] {
    if {[string match -nocase *.v $f]} { incr total }
}
puts "==== Fileset RTL now: $total (added $added) ===="

# 一致性判据：磁盘文件数 == 工程登记数，否则说明还有没登记的文件
if {$total != [llength $all]} {
    puts "==== WARNING: fileset ($total) != disk ([llength $all]) ===="
} else {
    puts "==== REFRESH OK ===="
}
