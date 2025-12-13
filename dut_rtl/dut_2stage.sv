module dut #(
  parameter int DRAM_ADDRESS_WIDTH = 32,
  parameter int SRAM_ADDRESS_WIDTH = 10,
  parameter int DRAM_DQ_WIDTH = 8,
  parameter int SRAM_DATA_WIDTH = 32
)(
  // System Signals
  input  wire                             clk           ,
  input  wire                             reset_n       , 
 
  // Control signals
  input  wire                             start         ,
  output wire                             ready         ,

  // DRAM Input memory interface
  output wire   [1:0]                     input_CMD     ,  // 2'b00=IDLE, 2'b01=READ, 2'b10=WRITE
  output wire   [DRAM_ADDRESS_WIDTH-1:0]  input_addr    ,
  input  wire   [DRAM_DQ_WIDTH-1:0]       input_dout    ,
  output wire   [DRAM_DQ_WIDTH-1:0]       input_din     ,
  output wire                             input_oe      ,

  // DRAM Output memory interface
  output wire   [1:0]                     output_CMD    ,  // 2'b00=IDLE, 2'b01=READ, 2'b10=WRITE
  output wire   [DRAM_ADDRESS_WIDTH-1:0]  output_addr   ,
  input  wire   [DRAM_DQ_WIDTH-1:0]       output_dout   ,
  output wire   [DRAM_DQ_WIDTH-1:0]       output_din    ,
  output wire                             output_oe     ,

  // Port A: Read Port 
  output reg  [SRAM_ADDRESS_WIDTH-1 :0] read_address  ,
  input  wire  [SRAM_DATA_WIDTH-1 :0]    read_data     ,
  output reg                            read_enable   , 
  
  //---------------------------------------------------------------
  // Port B: Write Port 
  output    reg  [SRAM_ADDRESS_WIDTH-1 :0] write_address ,
  output   reg  [SRAM_DATA_WIDTH-1 :0]    write_data    ,
  output   reg                            write_enable  

);
    // DRAM_in signals
    logic        en_ready;
    logic        kernel_flg;
    logic        data_flg;
    logic signed [7:0]  DRAM_data;

    // Staging_unit signals
    logic        done, final_packet_out;
    logic        capture;
    logic        ld_4x8;
    logic        ld_4x4;
    logic        shift_up;
    logic        shift_left;
    logic        squash;
    logic signed [7:0]  reg_file_out [3:0][7:0];
    
    // MAC_unit signals
    logic signed [7:0]  collector_out [7:0];
    logic        capture_out;


    // Instantiate DRAM_in
    DRAM_in dram_input (
        .clk            (clk),
        .rst_n          (reset_n),
        .CMD            (input_CMD),
        .addr           (input_addr),
        .dout           (input_dout),
        .din            (input_din),
        .oe             (input_oe),
        .start          (start),
        .ready          (ready),
        .en_ready       (en_ready),
        .kernel_flg     (kernel_flg),
        .data_flg       (data_flg),
        .DRAM_data      (DRAM_data),
        .done           (done)
    );

    Staging_unit staging_unit_inst (
        .clk            (clk),
        .rst_n          (reset_n),
        .kickoff        (data_flg),
        .final_packet   (done),
        .MAC_data       (DRAM_data),
        .rd_SRAM        (read_enable),
        .wr_SRAM        (write_enable),
        .SRAM_rd_addr   (read_address),
        .SRAM_wr_addr   (write_address),
        .SRAM_rd_data   (read_data),
        .SRAM_wr_data   (write_data),
        .capture        (capture),
        .ld_4x8         (ld_4x8),
        .ld_4x4         (ld_4x4),
        .shift_up       (shift_up),
        .shift_left     (shift_left),
        .squash         (squash),
        .final_packet_out (final_packet_out),
        .reg_file_out   (reg_file_out)
    );

    MAC_unit mac_unit_inst (
        .clk                (clk),
        .rst_n              (reset_n),
        .capture            (capture),
        .squash             (squash),
        .final_packet       (final_packet_out),
        .kernel_flg         (kernel_flg),
        .kernel_data        (DRAM_data),
        .ld_4x8             (ld_4x8),
        .data_in            (reg_file_out),
        .collector_out      (collector_out),
        .capture_p_out        (capture_out)
    );

    DRAM_out dram_output (
        .clk        (clk),
        .rst_n      (reset_n),
        .CMD        (output_CMD),
        .addr       (output_addr),
        .dout       (output_dout),
        .din        (output_din),
        .oe         (output_oe),
        .en_ready   (en_ready),
        .capture    (capture_out),
        .mac_data   (collector_out)
    );


endmodule

// -------------------- DRAM Input Module -----------------------------
module DRAM_in (
    input  logic                     clk,
    input  logic                     rst_n,
    // DRAM signals
    output logic      [1:0]          CMD,        // 2'b00=IDLE, 2'b01=READ, 2'b10=WRITE
    output logic      [31:0]         addr,
    input  logic      [7:0]          dout,
    output logic      [7:0]          din,
    output logic                     oe,
    // Control signals
    input  logic                     start,
    output logic                     ready,
    input  logic                     en_ready,
    output logic                     kernel_flg,
    output logic                     data_flg,
    output logic signed     [7:0]    DRAM_data,
    output logic                     done
);

    // State encoding
    typedef enum logic {
        IDLE  = 1'b0,
        COUNTING  = 1'b1
    } state_t;
    state_t i_state, i_state_next, j_state, j_state_next, k_state, k_state_next;
    logic [2:0] j, k, j_next, k_next;
    logic [2:0] i, i_next;

    logic signed [7:0] buffer_in [0:7];
    logic signed [7:0] buffer_in_next [0:7];
    logic signed [7:0] buffer_out [0:7];
    logic signed [7:0] buffer_out_next [0:7];
    logic [1:0] packet_count, packet_count_next;
    logic ready_next;
    logic [31:0] addr_next;



    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready <= 1'b1;
            addr <= 32'h00000000;
            j_state <= IDLE;
            i_state <= IDLE;
            k_state <= IDLE;
            j <= 3'd0;
            i <= 2'd0;
            k <= 3'd0;
            for (int idx = 0; idx < 8; idx++) begin
                buffer_in[idx] <= 8'b0;
                buffer_out[idx] <= 8'b0;
            end
            packet_count <= 2'd0;
        end
        else begin
            ready <= ready_next;
            addr <= addr_next;
            j_state <= j_state_next;
            i_state <= i_state_next;
            k_state <= k_state_next;
            j <= j_next;
            i <= i_next;
            k <= k_next;
            buffer_in <= buffer_in_next;
            buffer_out <= buffer_out_next;
            packet_count <= packet_count_next;
        end
    end

    always_comb begin
        // Default outputs
        CMD   = 2'b00; // IDLE
        din   = 8'b0;
        oe    = 1'b0; // Input mode for reading
        ready_next = ready;
        addr_next = addr;
        j_next = j;
        i_next = i;
        k_next = k;
        j_state_next = j_state;
        i_state_next = i_state;
        k_state_next = k_state;
        buffer_in_next = buffer_in;
        buffer_out_next = buffer_out;
        kernel_flg = 1'b0;
        data_flg = 1'b0;
        DRAM_data = 8'b0;
        packet_count_next = packet_count;
        done = 1'b0;

        case(k_state)
            IDLE: begin
                k_next = 3'd0;
                for (int idx = 0; idx < 8; idx++) begin
                    buffer_out_next[idx] = 8'b0;
                end
            end
            COUNTING: begin
                k_next = k + 3'd1;
                // Shift buffer_out right
                for (int idx = 0; idx < 7; idx++) begin
                    buffer_out_next[idx] = buffer_out[idx + 1];
                end
                buffer_out_next[7] = 8'b0;
                DRAM_data = buffer_out[0];  // Output current byte

                if (packet_count < 2'd2) begin
                    kernel_flg = 1'b1;
                end
                else begin
                    data_flg = 1'b1;
                end

                if (k == 3'd7) begin
                    if (packet_count < 2'd2) begin
                        packet_count_next = packet_count + 2'd1;
                    end
                    k_next = 3'd0;
                    k_state_next = IDLE;
                end
            end
        endcase
    
        case(j_state)
            IDLE: begin
                j_next = 3'd0;
                for (int idx = 0; idx < 8; idx++) begin
                    buffer_in_next[idx] = 8'b0;
                end
            end
            COUNTING: begin
                j_next = j + 3'd1;
                for (int idx = 7; idx > 0; idx--) begin     // Shift buffer_in taking in new data from dout
                    buffer_in_next[idx] = buffer_in[idx - 1];
                end
                buffer_in_next[0] = dout;
                if (j == 3'd7) begin
                    j_next = 3'd0;
                    for (int idx = 1; idx < 8; idx++) begin
                        buffer_out_next[idx] = buffer_in[idx - 1];
                    end
                    buffer_out_next[0] = dout;
                    k_state_next = COUNTING;
                    j_state_next = IDLE;
                end
            end
        endcase

        case (i_state)
            IDLE: begin
                i_next = 3'd0;
                if(en_ready) begin
                    ready_next = 1'b1;
                end
            end
            COUNTING: begin
                i_next = i + 3'd1;
                case (i)
                    3'd4: begin
                        addr_next = addr + 32'd8; // Increment address for new read
                        j_state_next = COUNTING;
                    end
                    3'd7: begin
                        CMD = 2'b01; // READ
                        i_next = 3'd0;
                    end
                endcase
            end
        endcase

        if(start) begin
            ready_next = 1'b0;
            CMD = 2'b01; // READ
            i_state_next = COUNTING;
        end

        if(addr == 32'h00100010) begin
            i_state_next = IDLE;
            done = 1'b1;
        end


    end
endmodule    

// ================== MAC Unit Modules ===================
module shift_buffer_1x4 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        shift_en,
    input  logic signed [7:0]  data_in,    // 1 byte input
    output logic signed [7:0]  data_out    
);

    // 4-byte shift register
    logic signed [7:0] shift_reg [3:0];

    // Shift control logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 4; i++) begin
                shift_reg[i] <= 8'h00;
            end
        end else if (shift_en) begin
            for (int i = 3; i > 0; i--) begin
                shift_reg[i] <= shift_reg[i-1];
            end
            shift_reg[0] <= data_in;  // Shift in new data at the front
        end else begin
            for (int i = 0; i < 4; i++) begin
                shift_reg[i] <= shift_reg[i];
            end
        end
    end

    assign data_out = shift_reg[3];
endmodule

module shift_reg_file_4x8 (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        load_enable,
    input  logic signed [31:0] SRAM_data,           

    input  logic signed [7:0]  DRAM_data_in,
    output logic signed [31:0] DRAM_data_out,

    input  logic        shift_up,   
    input  logic        shift_left,
    output logic signed [7:0]  reg_file_out [3:0][7:0] 
);

    logic signed [7:0] reg_file_right [3:0][3:0];  // Internal storage
    logic signed [7:0] reg_file_left [3:0][3:0];  // Internal storage

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int r = 0; r < 4; r++) begin
                for (int c = 0; c < 4; c++) begin
                    reg_file_right[r][c] <= 8'b0;
                    reg_file_left[r][c] <= 8'b0;
                end
            end
        end
        else begin
            // Load row 3 from SRAM
            reg_file_right[3][0] <= DRAM_data_in;
            reg_file_right[3][1] <= reg_file_right[3][0];
            reg_file_right[3][2] <= reg_file_right[3][1];
            reg_file_right[3][3] <= reg_file_right[3][2];
            reg_file_left[3][0] <= reg_file_right[3][3];
            reg_file_left[3][1] <= reg_file_left[3][0];
            reg_file_left[3][2] <= reg_file_left[3][1];
            reg_file_left[3][3] <= reg_file_left[3][2];
            
            // Shift rows 1 & 2 up
            if (shift_up) begin
                for (int c = 0; c < 4; c++) begin
                    for (int r = 0; r < 2; r++) begin
                        reg_file_right[r][c] <= reg_file_right[r + 1][c];
                    end
                end
            end
            
            if (shift_left) begin
                for (int c = 0; c < 4; c++) begin
                    reg_file_left[0][c] <= reg_file_right[0][c];
                    reg_file_left[1][c] <= reg_file_right[1][c];
                    reg_file_left[2][c] <= reg_file_right[2][c];
                end
            end
            // Load row 2 from SRAM
            if (load_enable) begin
                reg_file_right[2][0] <= SRAM_data[7:0];
                reg_file_right[2][1] <= SRAM_data[15:8];
                reg_file_right[2][2] <= SRAM_data[23:16];
                reg_file_right[2][3] <= SRAM_data[31:24];
            end


        end
    end

    assign DRAM_data_out = {reg_file_right[3][3], reg_file_right[3][2], reg_file_right[3][1], reg_file_right[3][0]};
    
    // Assign reg_file_out: [3:0][7:4] = left, [3:0][3:0] = right
    always_comb begin
        for (int r = 0; r < 4; r++) begin
            for (int c = 0; c < 4; c++) begin
                reg_file_out[r][c] = reg_file_right[r][c];     // columns 0-3
                reg_file_out[r][c+4] = reg_file_left[r][c];    // columns 4-7
            end
        end
    end
endmodule

module Controller(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        kickoff,
    input  logic        final_packet,
    output logic        final_packet_out,

    output logic [9:0]  SRAM_rd_addr,
    output logic [9:0]  SRAM_wr_addr,
    output logic        rd_sram,
    output logic        wr_sram,

    output logic        ld_4x4,
    output logic        ld_4x8,
    output logic        shift_up,
    output logic        shift_left,
    output logic        squash,

    output logic        capture
);

    typedef enum logic [1:0]  {
        IDLE  = 2'b00,
        STALL  = 2'b01,
        COUNTING  = 2'b10
    } state_t;

    state_t state, state_next;

    logic [1:0] i, i_next, j, j_next;
    logic [1:0] row, row_next;
    logic [7:0] col, col_next; 
    logic wr_sram_next;
    logic [9:0] SRAM_wr_addr_next;
    logic [2:0] row_count, row_count_next;
    logic shift_left_next;
    logic squash_next;
    logic final_packet_out_next;

    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            i <= 2'd0;
            j <= 2'd0;
            row <= 2'd1;
            col <= 8'd0;
            row_count <= 3'd0;
            wr_sram <= 1'b0;
            SRAM_wr_addr <= 10'd0;
            shift_left <= 1'b0;
            squash <= 1'b0;
            final_packet_out <= 1'b0;
        end
        else begin
            state <= state_next;
            i <= i_next;
            j <= j_next;
            row <= row_next;
            col <= col_next;
            row_count <= row_count_next;
            wr_sram <= wr_sram_next;
            SRAM_wr_addr <= SRAM_wr_addr_next;
            shift_left <= shift_left_next;
            squash <= squash_next;
            final_packet_out <= final_packet_out_next;
        end
    end

    always_comb begin
        state_next = state;
        row_next = row;
        col_next = col;
        row_count_next = row_count;
        i_next = i;
        j_next = j;
        shift_up = 1'b0;
        shift_left_next = 1'b0;
        ld_4x4 = 1'b0;
        rd_sram = 1'b0;
        wr_sram_next = 1'b0;  
        SRAM_wr_addr_next = SRAM_wr_addr;
        SRAM_rd_addr = {row, col};
        capture = 1'b0;
        ld_4x8 = 1'b0;
        squash_next = 1'b0;
        final_packet_out_next = 1'b0;

        case(state)
            IDLE: begin
                if (kickoff) begin
                    state_next = STALL;
                end
                i_next = 2'd0;
                j_next = 2'd0;
                row_next = 2'd1;
                col_next = 8'd0;
            end
            STALL: begin
                i_next = i + 2'd1;
                if (i == 2'd2) begin
                    i_next = 2'd0;
                    state_next = COUNTING;
                end
            end
            COUNTING: begin
                j_next = j + 2'd1;
                row_next = row + 2'd1;
                case (j)
                    2'd0: begin
                        rd_sram = 1'b1;
                        if (col == 8'd0) begin
                           if (row_count < 3'd4) begin
                                row_count_next = row_count + 3'd1;
                            end
                        end
                    end
                    2'd1: begin
                        rd_sram = 1'b1;
                        ld_4x4 = 1'b1;
                    end
                    2'd2: begin
                        rd_sram = 1'b1;
                        ld_4x4 = 1'b1;
                        shift_up = 1'b1;
                    end
                    2'd3: begin    
                        rd_sram = 1'b0;
                        ld_4x4 = 1'b1;
                        shift_up = 1'b1;
                        wr_sram_next = 1'b1;
                        SRAM_wr_addr_next = {row, col};
                        col_next = col + 8'd1;
                        shift_left_next = 1'b1;
                        if (col == 8'hFF) begin
                            row_next = row + 2'd2;
                            squash_next = 1'b1;
                            col_next = 8'd0;
                            if(final_packet) begin
                                state_next = IDLE;
                                final_packet_out_next = 1'b1;
                            end
                        end
                    end
                endcase
            end
            default: state_next = IDLE;
        endcase

        if(wr_sram) begin
            ld_4x8 = (row_count > 3'd3) ? (SRAM_wr_addr[0]) : 1'b0;
            capture = ld_4x8;
        end
    end
endmodule

module Staging_unit (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     kickoff,
    input  logic                     final_packet,
    input  logic      [7:0]          MAC_data,

    output logic                     rd_SRAM,
    output logic                     wr_SRAM,
    output logic      [9:0]          SRAM_rd_addr,
    output logic      [9:0]          SRAM_wr_addr,
    input  logic signed     [31:0]         SRAM_rd_data,
    output logic signed     [31:0]         SRAM_wr_data,

    output logic                     capture,
    output logic                     ld_4x8,
    output logic                     ld_4x4,
    output logic                     shift_up,
    output logic                     shift_left,
    output logic                     squash,
    output logic                     final_packet_out,
    output logic signed [7:0]        reg_file_out [3:0][7:0]
    );

    logic signed     [7:0] DRAM_buffer_out;
    

    Controller ctrl (
        .clk            (clk),
        .rst_n          (rst_n),
        .kickoff        (kickoff),
        .final_packet   (final_packet),
        .final_packet_out (final_packet_out),
        .SRAM_rd_addr   (SRAM_rd_addr),
        .SRAM_wr_addr   (SRAM_wr_addr),
        .rd_sram        (rd_SRAM),
        .wr_sram        (wr_SRAM),
        .ld_4x4         (ld_4x4),
        .ld_4x8         (ld_4x8),
        .shift_up       (shift_up),
        .shift_left     (shift_left),
        .squash         (squash),
        .capture        (capture)
    );

    shift_reg_file_4x8 reg_file (
        .clk            (clk),
        .rst_n          (rst_n),
        .load_enable    (ld_4x4),
        .SRAM_data      (SRAM_rd_data),
        .DRAM_data_in   (DRAM_buffer_out),
        .DRAM_data_out  (SRAM_wr_data),
        .shift_up       (shift_up),
        .shift_left     (shift_left),
        .reg_file_out   (reg_file_out)
    );


    shift_buffer_1x4 dram_buffer (
        .clk        (clk),
        .rst_n      (rst_n),
        .shift_en   (kickoff),
        .data_in    (MAC_data),
        .data_out   (DRAM_buffer_out)
    );
endmodule

// ================== MAC Unit Modules ===================

module kernel_4x4 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        shift_en,
    input  logic signed [7:0]  kernel_in,    // 1 byte input
    output logic signed [7:0]  kernel_out [3:0][3:0]   // Parallel 4 bytes output
);

    logic signed [7:0] registered_kernel [15:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 16; i++) begin
                registered_kernel[i] <= 8'h00;
            end
        end else if (shift_en) begin
            // Shift array elements right (higher indices to lower)
            for (int i = 0; i < 15; i++) begin
                registered_kernel[i] <= registered_kernel[i+1];
            end
            registered_kernel[15] <= kernel_in;  
        end
    end
    
    always_comb begin
        for (int r = 0; r < 4; r++) begin
            for (int c = 0; c < 4; c++) begin
                kernel_out[r][c] = registered_kernel[r*4 + c];
            end
        end
    end
endmodule

module shift_buffer_4x12 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        shift_en,
    input logic         ld_reg,    
    output  logic signed [7:0] data_out [3:0][3:0],   
    input logic signed [7:0]  data_in [3:0][7:0]   // Parallel 4x8 bytes output
);

    // 4x12-byte shift register
    logic signed [7:0] shift_reg [3:0][11:0];


    // Shift control logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int r = 0; r < 4; r++) begin
                for (int c = 0; c < 12; c++) begin
                    shift_reg[r][c] <= 8'h00;
                end
            end
        end else begin
            if (shift_en) begin
                // Shift array elements left (lower indices to higher)
                for (int r = 0; r < 4; r++) begin
                    for (int c = 11; c > 0; c--) begin
                        shift_reg[r][c] <= shift_reg[r][c-1];
                    end
                    shift_reg[r][0] <= 8'h00;
                end
            end
            if (ld_reg) begin
                // Load shift_reg[3:0][7:0] with data_in[3:0][7:0]
                for (int r = 0; r < 4; r++) begin
                    for (int c = 0; c < 8; c++) begin
                        shift_reg[r][c] <= data_in[r][c];
                    end
                end
            end
        end
    end

    // Output the upper 4 columns [11:8]
    always_comb begin
        for (int r = 0; r < 4; r++) begin
            for (int c = 0; c < 4; c++) begin
                data_out[r][c] = shift_reg[r][11-c];
            end
        end
    end

endmodule

module MAC_4x4 (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     squash,
    output logic                     squash_p,
    input  logic                     capture,
    output logic                     capture_p,
    input  logic signed [7:0]        data_in [3:0][3:0],   // 4 bytes input
    input  logic signed [7:0]        kernel_in [3:0][3:0],     // 4 bytes kernel
    output logic signed [7:0]        mac_out            // 8-bit MAC output
);


    // Stage 1: Between multiplier and accumulator
    logic signed [15:0] products_reg [3:0][3:0];
    logic squash_p1, capture_p1;

    // Stage 2: Between accumulator and output
    logic signed [19:0] sum_reg, sum;
    logic squash_p2, capture_p2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int r = 0; r < 4; r++) begin
                for (int c = 0; c < 4; c++) begin
                    products_reg[r][c] <= 16'sd0;
                end
            end
            sum_reg <= 20'sd0;
            squash_p2 <= 1'b0;
            capture_p2 <= 1'b0;
            squash_p1 <= 1'b0;
            capture_p1 <= 1'b0;
        end else begin
            for (int r = 0; r < 4; r++) begin
                for (int c = 0; c < 4; c++) begin
                    products_reg[r][c] <= data_in[r][c] * kernel_in[r][c];
                end
            end
            sum_reg <= sum;
            squash_p2 <= squash_p1;
            capture_p2 <= capture_p1;
            squash_p1 <= squash;
            capture_p1 <= capture;
        end
    end

    always_comb begin
        sum = 20'sd0;  // Initialize to zero first
        for (int r = 0; r < 4; r++) begin
            for (int c = 0; c < 4; c++) begin
                sum = sum + products_reg[r][c];
            end
        end
        
        if (sum_reg > 20'sd127) begin
            mac_out = 8'sd127;
        end else if (sum_reg < -20'sd128) begin
            mac_out = -8'sd128;
        end else begin
            mac_out = sum_reg[7:0];
        end
    end

    assign squash_p = squash_p2;
    assign capture_p = capture_p2;
endmodule

module MAC_collector (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        squash,
    input  logic signed [7:0]  mac_in,
    output logic signed [7:0]  collector_out [7:0]
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 8; i++) begin
                collector_out[i] <= 8'h00;
            end
        end 
        else begin 
            for (int i = 7; i > 0; i--) begin
                collector_out[i] <= collector_out[i-1];
            end
            collector_out[0] <= mac_in;  // Shift in new MAC data at the front
            if (squash) begin
                collector_out[0] <= 8'h00;
                collector_out[1] <= 8'h00;
                collector_out[2] <= 8'h00;
            end 
        end
    end
endmodule

module MAC_controller (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        capture_in,
    input  logic        final_packet,
    input  logic        squash_in,
    output logic        squash_out,
    output logic        capture_out
);
    typedef enum logic [1:0]  {
        IDLE  = 2'b00,
        STALL  = 2'b01,
        COUNTING  = 2'b10
    } state_t;

    state_t state, state_next;
    logic [2:0] i, i_next;
    logic squash_reg, squash_reg_next;
    logic final_packet_reg, final_packet_reg_next;
    logic final_packet_delay, final_packet_delay_next;
    logic squash_delay, squash_delay_next;
    logic capture_out_next;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            i <= 3'd0;
            squash_reg <= 1'b0;
            squash_delay <= 1'b0;
            final_packet_reg <= 1'b0;
            final_packet_delay <= 1'b0;
            capture_out <= 1'b0;
        end
        else begin
            state <= state_next;
            i <= i_next;
            squash_reg <= squash_reg_next;
            final_packet_reg <= final_packet_reg_next;
            final_packet_delay <= final_packet_delay_next;
            squash_delay <= squash_delay_next;
            capture_out <= capture_out_next;
        end
    end

    always_comb begin
        squash_out = 1'b0;
        capture_out_next = 1'b0;
        state_next = state;
        i_next = i;
        squash_reg_next = squash_reg;
        squash_delay_next = squash_delay;
        final_packet_reg_next = final_packet_reg;
        final_packet_delay_next = final_packet_delay;
        case(state)
            IDLE: begin
                i_next = 3'd0;
                squash_reg_next = 1'b0;
                final_packet_reg_next = 1'b0;
                if (capture_in) begin
                    state_next = STALL;
                    i_next = 3'd0;
                end
            end
            STALL: begin
                i_next = i + 3'd1;
                if (i == 3'd3) begin
                    i_next = 3'd0;
                    state_next = COUNTING;
                end
            end
            COUNTING: begin
                i_next = i + 3'd1;
                if (squash_in) begin
                    squash_reg_next = 1'b1;
                end
                if (final_packet) begin
                    final_packet_reg_next = 1'b1;
                end
                if (i == 3'd7) begin
                    capture_out_next = 1'b1;
                    if (squash_reg) begin
                        squash_delay_next = 1'b1;
                        squash_reg_next = 1'b0;
                    end
                    if (squash_delay) begin
                        squash_out = 1'b1;
                        squash_delay_next = 1'b0;
                    end
                    if (final_packet_reg) begin
                        final_packet_delay_next = 1'b1;
                        final_packet_reg_next = 1'b0;
                    end
                    i_next = 3'd0;
                    state_next = (final_packet_delay) ? IDLE : COUNTING;
                end
            end
            default: state_next = IDLE;
        endcase
    end
endmodule

module MAC_unit(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        capture,
    input  logic        squash,
    input  logic        final_packet,
    input  logic        kernel_flg,
    input  logic signed [7:0]  kernel_data,
    input  logic        ld_4x8,
    input  logic signed [7:0]  data_in [3:0][7:0],
    output logic signed [7:0]  collector_out [7:0],
    output logic        capture_p_out
);

    logic signed [7:0]  kernel_buffer_out [3:0][3:0];
    logic signed [7:0]  dram_buffer_out [3:0][3:0];
    logic signed [7:0]  mac_out;
    logic                     squash_out, squash_p_out;
    logic                     capture_out;

    kernel_4x4 kernel_buffer (
        .clk            (clk),
        .rst_n          (rst_n),
        .shift_en       (kernel_flg),
        .kernel_in      (kernel_data),
        .kernel_out     (kernel_buffer_out)
    );
    shift_buffer_4x12 mac_buffer (
        .clk            (clk),
        .rst_n          (rst_n),
        .shift_en       (1'b1),
        .ld_reg         (ld_4x8),
        .data_out       (dram_buffer_out),
        .data_in        (data_in)
    );
    MAC_controller mac_ctrl (
        .clk            (clk),
        .rst_n          (rst_n),
        .capture_in     (capture),
        .final_packet   (final_packet),
        .squash_in      (squash),
        .squash_out     (squash_out),
        .capture_out    (capture_out)
    );
    MAC_4x4 mac_unit_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .squash     (squash_out),
        .squash_p (squash_p_out),
        .capture    (capture_out),
        .capture_p (capture_p_out),
        .data_in    (dram_buffer_out),
        .kernel_in  (kernel_buffer_out),
        .mac_out    (mac_out)
    );
    MAC_collector colctr (
        .clk            (clk),
        .rst_n          (rst_n),
        .squash         (squash_p_out),
        .mac_in         (mac_out),
        .collector_out  (collector_out)
    );

endmodule

// ================== DRAM Interface Modules ===================

module DRAM_out (
    input  logic                     clk,
    input  logic                     rst_n,
    // DRAM signals
    output logic      [1:0]          CMD,        // 2'b00=IDLE, 2'b01=READ, 2'b10=WRITE
    output logic      [31:0]         addr,
    input  logic      [7:0]          dout,
    output logic      [7:0]          din,
    output logic                     oe,
    output logic                     en_ready,
    // Control signals
    input  logic                     capture,
    input  logic signed [7:0]        mac_data [7:0]
);

    logic signed [7:0] buffer_in [7:0];
    logic signed [7:0] buffer_in_next [7:0];
    logic signed [7:0] buffer_out [7:0];
    logic signed [7:0] buffer_out_next [7:0];
    logic [2:0] j, j_next;
    logic [1:0] i, i_next;
    logic [31:0] addr_next;

    typedef enum logic {
        IDLE  = 1'b0,
        COUNTING  = 1'b1
    } state_t;
    state_t j_state, i_state, j_state_next, i_state_next;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr <= 32'h00000000;
            j <= 3'd0;
            i <= 2'd0;
            for (int idx = 0; idx < 8; idx++) begin
                buffer_in[idx] <= 8'b0;
                buffer_out[idx] <= 8'b0;
            end
            j_state <= IDLE;
            i_state <= IDLE;
        end
        else begin
            addr <= addr_next;
            j <= j_next;
            i <= i_next;
            buffer_in <= buffer_in_next;
            buffer_out <= buffer_out_next;
            j_state <= j_state_next;
            i_state <= i_state_next;
        end
    end

    always_comb begin
        // Default outputs
        CMD   = 2'b00; // IDLE
        din   = 8'b0;
        oe    = 1'b1; // Output mode
        addr_next = addr;
        j_next = j;
        i_next = i;
        j_state_next = j_state;
        i_state_next = i_state;
        buffer_in_next = buffer_in;
        buffer_out_next = buffer_out;
        en_ready = 1'b0;

        case (j_state) 
            IDLE: begin
                j_next = 3'd0;
                if (addr > 32'h000ff3f8) begin
                    en_ready = 1'b1;
                    addr_next = 32'h00000000;
                end
            end
            COUNTING: begin
                j_next = j + 3'd1;
                din = buffer_out[0];
                for (int idx = 0; idx < 7; idx++) begin
                    buffer_out_next[idx] = buffer_out[idx + 1];
                end
                buffer_out_next[7] = 8'b0;
                case (j)
                    3'd7: begin
                        j_next = 3'd0;
                        j_state_next = IDLE;
                    end
                endcase
            end
        endcase

        case (i_state) 
            IDLE: begin
                i_next = 2'd0;
            end
            COUNTING: begin
                i_next = i + 2'd1;
                case (i)
                    2'd3: begin
                        buffer_out_next = buffer_in;
                        j_state_next = COUNTING;
                        i_state_next = IDLE;
                    end
                endcase
            end
        endcase

        if(capture) begin
            buffer_in_next = mac_data;
            CMD = 2'b10; // WRITE
            addr_next = addr + 32'd8; // Increment address for new write
            i_state_next = COUNTING;
        end

    end
endmodule


