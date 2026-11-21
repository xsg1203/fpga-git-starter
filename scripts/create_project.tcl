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

# RTL：rtl/*.v + rtl/<子目录>/*.v
set rtl_files [concat \
    [glob -nocomplain [file join $root_dir rtl *.v]] \
    [glob -nocomplain [file join $root_dir rtl * *.v]] ]
add_files -norecurse $rtl_files

add_files -fileset constrs_1 -norecurse [file join $root_dir constr ebaz4205.xdc]

set_property top ct_top [current_fileset]
update_compile_order -fileset sources_1

# 注意：以下两条 puts 刻意用纯 ASCII。
# Vivado 2017.4 在 Windows 批处理模式下按非 UTF-8 解析 Tcl 输出，中文会显示成
# "å·¥ç¨‹" 这类乱码，影响看日志。源码注释保留中文不影响执行。
puts "==== Project created: $proj_dir/$proj_name.xpr ===="
puts "==== RTL files: [llength $rtl_files] ===="
