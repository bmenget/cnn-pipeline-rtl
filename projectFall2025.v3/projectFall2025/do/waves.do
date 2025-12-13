add wave -noupdate -group tb sim:/tb/* 
add wave -noupdate -group dut_inst  sim:/tb/dut/* 
add wave -noupdate -group sdr_mem  sim:/tb/mem/* 
run -all
