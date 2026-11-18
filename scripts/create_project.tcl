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

puts "==== 工程已创建: $proj_dir/$proj_name.xpr ===="
puts "==== RTL 文件数: [llength $rtl_files] ===="
