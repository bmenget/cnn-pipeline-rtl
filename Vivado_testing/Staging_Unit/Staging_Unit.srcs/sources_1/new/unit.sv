module shift_buffer_1x4 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        shift_en,
    input  logic [7:0]  data_in,    // 1 byte input
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
    input  logic [31:0] SRAM_data,           

    input  logic [7:0]  DRAM_data_in,
    output logic [31:0] DRAM_data_out,

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
                if (i == 2'd1) begin
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
                        if (col == 8'h03) begin
                            row_next = row + 2'd2;
                            squash_next = 1'b1;
                            col_next = 8'd0;
                            state_next = (final_packet) ? IDLE : COUNTING;
                        end
                    end
                endcase
            end
            default: state_next = IDLE;
        endcase

        if(wr_sram) begin
            ld_4x8 = (SRAM_wr_addr[0]) ? 1'b1 : 1'b0;
            capture = (row_count > 3'd3) ? ld_4x8 : 1'b0;
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
    input  logic      [31:0]         SRAM_rd_data,
    output logic      [31:0]         SRAM_wr_data,

    output logic                     capture,
    output logic                     ld_4x8,
    output logic                     ld_4x4,
    output logic                     shift_up,
    output logic                     shift_left,
    output logic                     squash,
    output logic signed [7:0]        reg_file_out [3:0][7:0]
    );

    logic        [7:0] DRAM_buffer_out;
    

    Controller ctrl (
        .clk            (clk),
        .rst_n          (rst_n),
        .kickoff        (kickoff),
        .final_packet   (final_packet),
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
