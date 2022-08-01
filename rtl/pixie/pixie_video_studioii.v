//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 0210-1301 USA.
//
//============================================================================

module pixie_video_studioii
(
    // back end, video clock domain
    input               clk,
    input               reset, 

    output              csync,
    output  reg         video,

    output              VSync,
    output              HSync,    
    output              VBlank,
    output              HBlank,
    output              video_de,      

    // front end, CDP1802 bus clock domain
    input              clk_enable,
    input        [1:0] SC,
    input              disp_on,
    input              disp_off,
    input        [7:0] data_in,

    output reg         DMAO,
    output reg         INT,
    output reg         EFx,

    output reg  [15:0] mem_addr,
    output reg         mem_req,
    input  reg         mem_ack    
);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

parameter  pixels_per_line    = 112; // (14bytes x 8bits, constant for all 1861's)
parameter  bytes_per_line     = 14;  // 
parameter  active_h_pixels    = 64;  // (studio2 has 64 active pixels per visible horizontal row) 
parameter  hsync_start_pixel  = 2;   // two cycles later to account for pipeline delay
parameter  hsync_width_pixels = 12;  

parameter  lines_per_frame    = 262; // (constant for all 1861's) 
parameter  active_v_lines     = 128; // (NTSC (PAL is 192. There is no PAL natively on StudioII))
parameter  vsync_start_line   = 2;  
parameter  vsync_height_lines = 12;  // 6

parameter  start_addr         = 'h0900;
parameter  end_addr           = start_addr + 'hff;

//PAL
// interruptGraphicsMode_ = 74;
// startGraphicsMode_     = 76;
// endGraphicsMode_       = 267;
// endScreen_             = 312;
// videoHeight_           = 192;

//NTSC
// interruptGraphicsMode_ = 62;
// startGraphicsMode_     = 64;
// endGraphicsMode_       = 191;
// endScreen_             = 262;
// videoHeight_           = 128;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

reg   [7:0] pixel_shift_reg;
  
reg   [7:0] horizontal_counter;
reg         hsync;
reg         advance_v;
    
reg   [8:0] vertical_counter;
reg         vsync;

reg   [8:0] new_v;
reg   [7:0] new_h;

reg         SC_fetch;
reg         SC_execute;
reg         SC_dma;
reg         SC_interrupt;

reg         enabled;

reg         DMA_xfer;
reg   [9:0] addr_counter;

reg   [7:0] row_cache[8];
reg   [7:0] row_cache_counter;
reg         row_cache_ready;

reg   [7:0] cycle_counter;
reg  [15:0] vram_addr = start_addr;
reg         advance_addr;

////////////////////////// assignments  ////////////////////////////////////////////////////////////////////////////////

assign DMAO      = (enabled && VBlank==1'b0 && horizontal_counter >= 1 && horizontal_counter < 9) ? 1'b0 : 1'b1;
assign DMA_xfer  = (enabled && SC_dma) ? 1'b1 : 1'b0;

assign mem_wr_en = DMA_xfer;

assign csync     = ~(HSync ^ VSync);
assign video_de  = ~(VBlank && HBlank);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

always @(posedge clk) begin
    case (SC)
      2'b00: SC_fetch     <= 1'b1;
      2'b01: SC_execute   <= 1'b1;
      2'b10: SC_dma       <= 1'b1;
      2'b11: SC_interrupt <= 1'b1;                  
    endcase

    if (clk_enable) begin
      if(reset)
        enabled <= 1'b0;
      else if (disp_on)
        enabled <= 1'b1;
      else if (disp_off)
        enabled <= 1'b0;
    end
end

// State machine constants
localparam SM_LOAD_CACHE = 0;
localparam SM_OUTPUT_VIDEO = 1;
reg [7:0] state = SM_LOAD_CACHE;

reg [7:0] nbit;
reg [7:0] byte_counter;
reg load_byte = 1'b1;
// 1. Read 8 bytes from vram into row cache
always @(posedge clk) begin
    if (enabled) begin
      case (state)
        SM_LOAD_CACHE:
          begin
            // if at end of display, reset regs
            if (vram_addr == end_addr+1) begin
                vram_addr <= start_addr;
                row_cache_counter <= 0;
                row_cache_ready <= 1'b0;    
                //$display("vram_addr == end_addr");                       
            end
            else begin
              // reset row cache counter if at 8
              if (row_cache_counter == 8) begin
                row_cache_counter <= 0;
                row_cache_ready <= 1'b1;
                mem_req <= 1'b0;  
                //$display("row_cache_counter == 8");    
                state <= SM_OUTPUT_VIDEO;                      
              end
              else begin
                if(mem_ack) begin
                  // load a byte from vram into row cache    
                  row_cache[row_cache_counter-1] <= data_in;            
                  row_cache_counter <= row_cache_counter + 1;
                  row_cache_ready <= 1'b0;
                  mem_addr <= vram_addr;
                  vram_addr <= vram_addr + 1;              
                  mem_req <= 1'b1;    
                  //$display("vram into row cache: vram_addr %h data_in %h row_cache_counter %h", vram_addr, data_in, row_cache_counter);                        
                end
              end
            end
          end   
        SM_OUTPUT_VIDEO:     
          begin
            if(video_de) begin
              //$display("SM_OUTPUT_VIDEO");
              if(load_byte == 1'b1) begin
                // load a byte from row_cache into pixel_shift_reg
                pixel_shift_reg <= row_cache[byte_counter];
                load_byte = 1'b0;
                //$display("pixel_shift_reg %h byte_counter %h", pixel_shift_reg, byte_counter);              
                end
              else begin
                // process the byte to video
                video <= pixel_shift_reg[7];   
                pixel_shift_reg <= {pixel_shift_reg[6:0], 1'b0};                        

                nbit <= nbit + 1'd1;
                // advance the byte counter
                if (nbit == 8'd7) begin
                  nbit <= 8'd0;
                  load_byte = 1'b1;  
                  byte_counter <= byte_counter + 1'd1;              
                end

                if(byte_counter == 8'd7) begin
                  // when all done return to load cache state  
                  byte_counter <= 8'd0;           
                  state <= SM_LOAD_CACHE;
                end
                $display("pixel_shift_reg %h video %h, byte_counter %h, load_byte %h, nbit %h", pixel_shift_reg, video, byte_counter, load_byte, nbit);
            end
          end
        end
      endcase
    end
end

// 3. Repeat until all vram is read
always @(posedge clk) begin
end


// Create HSync and HBlank
always @(posedge clk) begin
  if (horizontal_counter == (pixels_per_line-1)) begin
    new_h <= 1'd0;
    advance_v <= 1'b1;
  end
  else begin
    new_h <= horizontal_counter + 1'd1;
  end

  horizontal_counter <= new_h;
  HSync <= (new_h < (hsync_start_pixel+hsync_width_pixels)) ? 1'b1 : 1'b0;  
  HBlank <= (horizontal_counter < 18 || horizontal_counter > 82)  ? 1'b1 : 1'b0;  // 64 pixels wide
end

// Create VSync and VBlank
always @(posedge clk) begin
  if(advance_v) begin
    advance_v <= 0;
    if (vertical_counter==(lines_per_frame-1))
      new_v <= 1'd0;
    else begin
      new_v <= vertical_counter + 1'b1;
    end
  end

  vertical_counter <= new_v;
  VSync <= (new_v < (vsync_start_line+vsync_height_lines)) ? 1'b1 : 1'b0;
  VBlank <= (vertical_counter < 64 || vertical_counter > 192) ? 1'b1 : 1'b0;  // 128 lines for NTSC  
end

endmodule
