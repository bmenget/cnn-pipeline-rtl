
`timescale 1ns/1ps
// `default_nettype none
`ifndef ADDR_WIDTH
`define ADDR_WIDTH 32
`endif
module tb;
  //--------------------------------------------------------------------------
  // Clock @ 100 MHz
  //--------------------------------------------------------------------------
  logic clk; initial clk = 1'b0; always #5 clk = ~clk;

  //string input_dir = "/home/jasteve4/TA/ECE-564-fall2025/project-dev/inputs";
  //string output_dir = "/home/jasteve4/TA/ECE-564-fall2025/project-dev/outputs";
  string input_dir =  "";
  integer file_handle;

  //--------------------------------------------------------------------------
  // Runtime-config knobs (read from +plusargs)
  //   +tb_dqwidth=<N>      (fallback: +mc_dqwidth)
  //   +tb_burstlen=<N>     (fallback: +mc_burstlen, default 8)
  //   +tb_rdlat=<N>        (fallback: +mc_rdlat,   default -1 => wait for non-Z)
  //--------------------------------------------------------------------------
  localparam ADDR_WIDTH      = 12;   
  localparam DATA_WIDTH      = 32;   


  //--------------------------------------------------------------------------
  // Bus + TB-side IO
  //--------------------------------------------------------------------------

  // Port A: Read Port 
  reg  [ADDR_WIDTH-1 :0]     read_address       ;
  wire [DATA_WIDTH-1 :0]     read_data   ;
  reg                        read_enable         ; 
  
  //---------------------------------------------------------------
  // Port B: Write Port 
  reg  [ADDR_WIDTH-1 :0]     write_address       ;
  reg  [DATA_WIDTH-1 :0]     write_data  ;
  reg                        write_enable         ;

  sram1r1w
      #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH) 
      )
      sram
      (
        // General
        .clk        (clk),    

        //---------------------------------------------------------------
        // Port A: Read Port 
        .read_address       (read_address  ),
        .read_data          (read_data     ),
        .read_enable        (read_enable   ), 
        
        //---------------------------------------------------------------
        // Port B: Write Port 
        .write_address      (write_address ),
        .write_data         (write_data    ),
        .write_enable       (write_enable  ) 
      );


  //--------------------------------------------------------------------------
  // Helpers & Tasks
  //--------------------------------------------------------------------------
  // Place in a package or before any initial/always blocks

  initial begin

    $display("[TB] start");
    $dumpfile("waves.vcd"); $dumpvars(0, tb);
    read_address       = 'h0;
    read_enable         = 1'b0; 
    write_address       = 'h0;
    write_data  = 'b0;
    write_enable         = 1'b0; 
    repeat (5) @(posedge clk);
    write_address       = 12'h008;
    write_data  = 32'hDEADBEEF;
    write_enable         = 1'b1;
    @(posedge clk);
    write_address       = 'h0;
    write_data  = 'h0;
    write_enable         = 1'b0;
    read_enable         = 1'b1;
    read_address       = 12'h008;
    @(posedge clk);
    read_enable         = 1'b0;
    read_address       = 12'h0;
    repeat (5) @(posedge clk);

    @(posedge clk);
    read_enable         = 1'b1;
    read_address       = 12'h100;
    write_address       = 12'h100;
    write_enable         = 1'b1;
    write_data  = 'hFEEDBEEF;
    @(posedge clk);
    write_enable         = 1'b0;
    @(posedge clk);
    read_address       = 12'h0;
    repeat (5) @(posedge clk);
    read_enable         = 1'b0;
    repeat (5) @(posedge clk);
    repeat (5) @(posedge clk);
    write_enable        = 1'b1;
    write_address       = 'h0;
    write_data          = 'h10;
    @(posedge clk);
    write_address       = 'h1;
    write_data          = 'h20;
    @(posedge clk);
    write_address       = 'h2;
    write_data          = 'h30;
    @(posedge clk);
    write_address       = 'h3;
    write_data          = 'h40;
    @(posedge clk);
    write_enable         = 1'b0;
    repeat (5) @(posedge clk);

    write_enable        = 1'b1;
    read_enable         = 'h1;
    write_address       = 'h0;
    write_data          = 'h0;
    read_address        = 'h0;
    @(posedge clk);
    write_address       = 'h1;
    write_data          = 'h1;
    read_address        = 'h1;
    @(posedge clk);
    write_address       = 'h2;
    write_data  = 'h2;
    read_address        = 'h2;
    @(posedge clk);
    write_address       = 'h3;
    write_data  = 'h3;
    read_address        = 'h3;
    @(posedge clk);
    write_enable         = 1'b0;
    read_enable         = 'h0;

    repeat (5) @(posedge clk);

    write_enable        = 1'b1;
    write_address       = 'h0;
    write_data          = 'hBEEF0001;
    @(posedge clk);
    write_address       = 'h1;
    write_data          = 'hBEEF0002;
    read_enable         = 'h1;
    read_address        = 'h0;
    @(posedge clk);
    write_address       = 'h2;
    write_data          = 'hBEEF0003;
    read_address        = 'h1;
    @(posedge clk);
    write_address       = 'h3;
    write_data          = 'hBEEF0004;
    read_address        = 'h2;
    @(posedge clk);
    write_enable        = 1'b0;
    read_address        = 'h3;
    @(posedge clk);
    read_enable         = 'h0;

    repeat (5) @(posedge clk);

    

    $display("[TB] done");
    $finish;
  end
endmodule

