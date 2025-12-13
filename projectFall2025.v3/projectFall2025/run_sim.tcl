# Vivado simulation script for shifter SRAM timing test

# Create project in memory (no files written to disk)
create_project -in_memory -part xc7a35tcpg236-1

# Add source files
add_files {srcs/rtl/dut.sv}
add_files {srcs/tb/sram1r1w.sv}
add_files -fileset sim_1 {srcs/tb/test_shifter_sram_timing.sv}

# Set top module
set_property top test_shifter_sram_timing [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sim_1

# Launch simulation
launch_simulation

# Run simulation for 500ns
run 500ns

# Print results
puts "\n=== Simulation Complete ==="
puts "Check the Tcl console output above for test results"
puts "Waveform available in Vivado GUI if running in GUI mode"

# Close simulation
close_sim -force
