# 创建 Vivado 工程（Vivado 2017.4）
# 用法（在工程根目录）：
#   vivado -mode batch -source scripts/create_project.tcl
# 或 GUI：
#   vivado -source scripts/create_project.tcl

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]

set proj_name "ct_ebaz4205"
set proj_dir  [file join $root_dir build]
set part_name "xc7z010clg400-1"

create_project $proj_name $proj_dir -part $part_name -force
set_property target_language Verilog [current_project]

# RTL：递归收集 rtl/ 下所有 .v
#
# 原来写的是 glob rtl/*.v + rtl/*/*.v（只到一层）。改成递归 proc：
#   - 深一层目录会被静默漏掉，而漏掉的表现是综合阶段
#     "ERROR: [Synth 8-439] module 'xxx' not found"，极易误判成代码问题；
#   - 顺手把每个文件的相对路径打印出来，出问题时一眼能看出漏了哪个。
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
puts "==== RTL list ([llength $rtl_files]) ===="
foreach f $rtl_files {
    puts "  [string range $f [expr {[string length $root_dir] + 1}] end]"
}
add_files -norecurse $rtl_files

add_files -fileset constrs_1 -norecurse [file join $root_dir constr ebaz4205.xdc]

set_property top ct_top [current_fileset]
update_compile_order -fileset sources_1

# 注意：以下两条 puts 刻意用纯 ASCII。
# Vivado 2017.4 在 Windows 批处理模式下按非 UTF-8 解析 Tcl 输出，中文会显示成
# "å·¥ç¨‹" 这类乱码，影响看日志。源码注释保留中文不影响执行。
puts "==== Project created: $proj_dir/$proj_name.xpr ===="
puts "==== RTL files: [llength $rtl_files] ===="
