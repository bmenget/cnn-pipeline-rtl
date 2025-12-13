`timescale 1ns / 1ps

module tb;

    // Clock and reset
    logic clk;
    logic rst_n;
    
    // Inputs
    logic kickoff;
    logic final_packet;
    logic [7:0] MAC_data;
    logic [31:0] SRAM_rd_data;
    logic kernel_flg;
    logic [7:0] kernel_data;
    
    // Outputs
    logic rd_SRAM;
    logic wr_SRAM;
    logic [9:0] SRAM_rd_addr;
    logic [9:0] SRAM_wr_addr;
    logic [31:0] SRAM_wr_data;
    logic capture;
    logic ld_4x8;
    logic ld_4x4;
    logic shift_up;
    logic shift_left;
    logic squash;
    logic signed [7:0] reg_file_out [3:0][7:0];
    
    // MAC_unit outputs
    logic [7:0] collector_out [7:0];
    logic capture_out;
    logic squash_out;
    logic signed [7:0] buffer_4x12 [3:0][11:0];
    logic signed [7:0] kernel_out [3:0][3:0];
    
    // Testbench variables
    logic [7:0] data_counter;
    logic [31:0] sram_memory [0:1023];
    logic first_capture_seen;
    logic kernel_loaded;
    
    // Instantiate DUT
    Staging_unit dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .kickoff        (kickoff),
        .final_packet   (final_packet),
        .MAC_data       (MAC_data),
        .rd_SRAM        (rd_SRAM),
        .wr_SRAM        (wr_SRAM),
        .SRAM_rd_addr   (SRAM_rd_addr),
        .SRAM_wr_addr   (SRAM_wr_addr),
        .SRAM_rd_data   (SRAM_rd_data),
        .SRAM_wr_data   (SRAM_wr_data),
        .capture        (capture),
        .ld_4x8         (ld_4x8),
        .ld_4x4         (ld_4x4),
        .shift_up       (shift_up),
        .shift_left     (shift_left),
        .squash         (squash),
        .reg_file_out   (reg_file_out)
    );
    
    // Instantiate MAC_unit
    MAC_unit mac (
        .clk            (clk),
        .rst_n          (rst_n),
        .capture        (capture),
        .squash         (squash),
        .final_packet   (final_packet),
        .kernel_flg     (kernel_flg),
        .kernel_data    (kernel_data),
        .ld_4x8         (ld_4x8),
        .data_in        (reg_file_out),
        .collector_out  (collector_out),
        .capture_out    (capture_out),
        .squash_out     (squash_out)
    );
    
    // Clock generation (10ns period = 100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // SRAM read response
    always_ff @(posedge clk) begin
        if (rd_SRAM) begin
            SRAM_rd_data <= sram_memory[SRAM_rd_addr];
        end
    end
    
    // SRAM write handling
    always_ff @(posedge clk) begin
        if (wr_SRAM) begin
            sram_memory[SRAM_wr_addr] <= SRAM_wr_data;
        end
    end
    
    // Capture first_capture flag
    logic kernel_flg_prev;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            first_capture_seen <= 1'b0;
            kernel_loaded <= 1'b0;
            kernel_flg_prev <= 1'b0;
        end else begin
            kernel_flg_prev <= kernel_flg;
            if (capture) begin
                first_capture_seen <= 1'b1;
            end 
            if (kernel_flg_prev && !kernel_flg && !kernel_loaded) begin
                kernel_loaded <= 1'b1;
            end
        end
    end
    
    // Monitor 4x12 buffer internal state
    assign buffer_4x12 = mac.mac_buffer.shift_reg;
    assign kernel_out = mac.kernel_buffer.kernel_out;
    
    // Print kernel after it's loaded (delayed by one cycle after kernel_flg goes low)
    always_ff @(posedge clk) begin
        if (rst_n && kernel_flg_prev && !kernel_flg) begin
            $write("Kernel loaded:\n");
            $write("%02h %02h %02h %02h\n", kernel_out[0][0], kernel_out[0][1], kernel_out[0][2], kernel_out[0][3]);
            $write("%02h %02h %02h %02h\n", kernel_out[1][0], kernel_out[1][1], kernel_out[1][2], kernel_out[1][3]);
            $write("%02h %02h %02h %02h\n", kernel_out[2][0], kernel_out[2][1], kernel_out[2][2], kernel_out[2][3]);
            $write("%02h %02h %02h %02h\n", kernel_out[3][0], kernel_out[3][1], kernel_out[3][2], kernel_out[3][3]);
            $write("Internal registered_kernel[0:15]: ");
            for (int i = 0; i < 16; i++) begin
                $write("%02h ", mac.kernel_buffer.registered_kernel[i]);
            end
            $write("\n");
            $write("========================================\n");
        end
    end
    
    // Print after first capture only
    always_ff @(posedge clk) begin
        if (rst_n && first_capture_seen) begin
            $write("ld_4x4=%b ld_4x8=%b shift_up=%b shift_left=%b squash=%b capture=%b\n",
                ld_4x4, ld_4x8, shift_up, shift_left, squash, capture);
            $write("capture_out=%b squash_out=%b\n", capture_out, squash_out);
            // Print 4x12 buffer (column 11 on left, 0 on right)
            $write("4x12 Buffer:\n");
            $write("%02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h\n",
                buffer_4x12[0][11], buffer_4x12[0][10], buffer_4x12[0][9], buffer_4x12[0][8],
                buffer_4x12[0][7], buffer_4x12[0][6], buffer_4x12[0][5], buffer_4x12[0][4],
                buffer_4x12[0][3], buffer_4x12[0][2], buffer_4x12[0][1], buffer_4x12[0][0]);
            $write("%02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h\n",
                buffer_4x12[1][11], buffer_4x12[1][10], buffer_4x12[1][9], buffer_4x12[1][8],
                buffer_4x12[1][7], buffer_4x12[1][6], buffer_4x12[1][5], buffer_4x12[1][4],
                buffer_4x12[1][3], buffer_4x12[1][2], buffer_4x12[1][1], buffer_4x12[1][0]);
            $write("%02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h\n",
                buffer_4x12[2][11], buffer_4x12[2][10], buffer_4x12[2][9], buffer_4x12[2][8],
                buffer_4x12[2][7], buffer_4x12[2][6], buffer_4x12[2][5], buffer_4x12[2][4],
                buffer_4x12[2][3], buffer_4x12[2][2], buffer_4x12[2][1], buffer_4x12[2][0]);
            $write("%02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h %02h\n",
                buffer_4x12[3][11], buffer_4x12[3][10], buffer_4x12[3][9], buffer_4x12[3][8],
                buffer_4x12[3][7], buffer_4x12[3][6], buffer_4x12[3][5], buffer_4x12[3][4],
                buffer_4x12[3][3], buffer_4x12[3][2], buffer_4x12[3][1], buffer_4x12[3][0]);
            $write("Collector Output: %02h %02h %02h %02h %02h %02h %02h %02h\n",
                collector_out[7], collector_out[6], collector_out[5], collector_out[4],
                collector_out[3], collector_out[2], collector_out[1], collector_out[0]);
            $write("----------------------------------------\n");
        end
    end
    
    // Main test sequence
    initial begin
        // Initialize
        rst_n = 0;
        kickoff = 0;
        final_packet = 0;
        MAC_data = 8'h00;
        data_counter = 8'h00;
        kernel_flg = 0;
        kernel_data = 8'h01;
        
        // Reset
        repeat(5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        
        // Load kernel first (16 bytes with kernel_flg high)
        kernel_flg = 1;
        repeat(16) begin
            kernel_data = 8'h01;
            $display("Loading kernel byte at time %0t", $time);
            @(posedge clk);
        end
        kernel_flg = 0;
        @(posedge clk); // Wait one more cycle for kernel to stabilize
        
        // Start kickoff and begin streaming data
        kickoff = 1;
        
        // Stream 200 cycles of incrementing byte data
        repeat(220) begin
            MAC_data = data_counter;
            data_counter = data_counter + 8'h01;
            @(posedge clk);
        end
        
        // Continue for a bit more
        repeat(50) @(posedge clk);
        
        $display("Simulation complete");
        $finish;
    end

endmodule
