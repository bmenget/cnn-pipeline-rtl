
module sram1r1w
    #(
      parameter ADDR_WIDTH = 10,
      parameter DATA_WIDTH = 32 
    )
    (
      //---------------------------------------------------------------
      // General
      input wire clk        ,    

      //---------------------------------------------------------------
      // Port A: Read Port 
      input   wire  [ADDR_WIDTH-1 :0]     read_address       ,
      output  wire  [DATA_WIDTH-1 :0]     read_data   ,
      input   wire                        read_enable         , 
      
      //---------------------------------------------------------------
      // Port B: Write Port 
      input   wire  [ADDR_WIDTH-1 :0]     write_address       ,
      input   wire  [DATA_WIDTH-1 :0]     write_data  ,
      input   wire                        write_enable          
    );

  reg  [DATA_WIDTH-1 :0] mem     [1<<ADDR_WIDTH] ;

  reg  [DATA_WIDTH-1 :0] reg_read_data;

  always @(posedge clk)
    begin
      reg_read_data   <= ( read_enable ) ? mem [read_address] : 
                                'bx ;
    end

  always @(posedge clk)
    begin
      if (write_enable)
        mem [write_address] <= write_data ;
    end

  assign read_data = reg_read_data  ;


endmodule


