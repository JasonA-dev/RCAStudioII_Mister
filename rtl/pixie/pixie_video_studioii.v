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

    output  reg         VSync,
    output  reg         HSync,    
    output  reg         VBlank,
    output  reg         HBlank,
    output              video_de,      

    // front end, CDP1802 bus clock domain
    input              clk_enable,
    input        [1:0] SC,
    input              disp_on,
    input              disp_off,
    input        [7:0] data_in,

    output wire        DMAO,
    output reg         INT,
    output reg         EFx,

    output reg  [15:0] mem_addr
);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

parameter  pixels_per_line    = 112; // (14 bytes x 8bits, constant for all 1861's)
parameter  bytes_per_line     = 14;  // 
parameter  active_h_pixels    = 64;  // (studio2 has 64 active pixels per visible horizontal row) 
parameter  hsync_start_pixel  = 2;   // two cycles later to account for pipeline delay
parameter  hsync_width_pixels = 12;   // 12

parameter  lines_per_frame    = 262; // (constant for all 1861's) 
parameter  active_v_lines     = 128; // (NTSC (PAL is 192. There is no PAL natively on StudioII))
parameter  vsync_start_line   = 2;  
parameter  vsync_height_lines = 6;   // 

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

reg   [7:0] horizontal_pixel_counter;  
reg   [7:0] horizontal_counter;
reg         hsync;
reg         advance_v;

reg         halt_horizontal_pixel_counter = 1'b0;
reg         halt_vertical_pixel_counter   = 1'b0;

reg   [8:0] vertical_pixel_counter;
reg   [8:0] vertical_counter;
reg         vsync;

reg         SC_fetch;
reg         SC_execute;
reg         SC_dma;
reg         SC_interrupt;

reg         display_enabled;

wire        DMA_xfer;

reg   [7:0] row_cache[8];
reg   [7:0] row_cache_counter = 0;
reg         row_cache_ready;

reg  [15:0] vram_addr = start_addr;
reg         advance_addr;

reg         start_pixel = 1'b0;

reg   [7:0] frame_buffer[256];
reg  [15:0] fb_addr = start_addr;

////////////////////////// assignments  ////////////////////////////////////////////////////////////////////////////////

assign DMAO      = (display_enabled && VBlank==1'b0 && horizontal_counter >= 1 && horizontal_counter < 9) ? 1'b0 : 1'b1;
assign DMA_xfer  = (display_enabled && SC_dma) ? 1'b1 : 1'b0;

assign csync     = ~(HSync ^ VSync);
assign video_de  = ~(VBlank | HBlank);

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
        display_enabled <= 1'b0;
      else if (disp_on)
        display_enabled <= 1'b1;
      else if (disp_off)
        display_enabled <= 1'b0;
    end
end

reg [7:0] nbit;
reg load_byte = 1'b1;
reg [3:0] line_repeat_counter = 3'd0;

always @(negedge clk) begin
  frame_buffer[fb_addr-2] <= data_in;    
  fb_addr <= vram_addr-start_addr;
  mem_addr <= vram_addr;      
  vram_addr <= vram_addr + 1;   

  if (vram_addr == end_addr) begin
    vram_addr <= start_addr;
  end               
end

// Video State Machine constants
localparam SM_READ_ROW = 0;
localparam SM_GENERATE_PIXELS = 1;
reg [7:0] video_state = SM_READ_ROW;

reg [15:0] video_byte_counter = 0;
reg  [7:0] byte_counter = 0;

always @(posedge clk) begin

  // Count horizontal pixels
  if(halt_horizontal_pixel_counter == 1'b0) begin
    horizontal_pixel_counter <= horizontal_pixel_counter + 1'd1;
  end
  if (horizontal_pixel_counter == pixels_per_line) begin
    horizontal_pixel_counter <= 0;
  end

  // Count vertical pixels
  if(halt_vertical_pixel_counter == 1'b0) begin
    vertical_pixel_counter <= vertical_pixel_counter + 1'd1;
  end
  if (vertical_pixel_counter == lines_per_frame) begin
    vertical_pixel_counter <= 0;
  end

  if(VBlank==1'b0 && HBlank==1'b0) begin
    halt_horizontal_pixel_counter <= 1'b1;
    halt_vertical_pixel_counter <= 1'b1;    
    
    case (video_state)
      SM_READ_ROW: begin
        row_cache[row_cache_counter] <= frame_buffer[row_cache_counter+video_byte_counter];
        //$display("SM_READ_ROW row_cache_counter %d video_byte_counter %d row_cache[row_cache_counter] %h vertical_pixel_counter %d horizontal_pixel_counter %d", 
        //            row_cache_counter, video_byte_counter, row_cache[row_cache_counter], vertical_pixel_counter, horizontal_pixel_counter);

        if (row_cache_counter == 7) begin
          row_cache_counter <= 0;
          video_byte_counter <= video_byte_counter + 8;    
          video_state <= SM_GENERATE_PIXELS;                 
        end  
        else begin
          row_cache_counter <= row_cache_counter + 1;  
        end

        if (video_byte_counter >= 256) begin
          video_byte_counter <= 0;
        end    
      end

      SM_GENERATE_PIXELS: begin
        if(load_byte) begin
          pixel_shift_reg <= row_cache[byte_counter];
          load_byte <= 0;
          //$display("SM_GENERATE_PIXELS load_byte byte_counter %d pixel_shift_reg %h row_cache[byte_counter] %h vertical_pixel_counter %d horizontal_pixel_counter %d line_repeat_counter %d",
          //            byte_counter, pixel_shift_reg, row_cache[byte_counter], vertical_pixel_counter, horizontal_pixel_counter, line_repeat_counter);               
        end
        else begin
          //$display("SM_GENERATE_PIXELS byte_counter %d pixel_shift_reg %h video %h vertical_pixel_counter %d horizontal_pixel_counter %d line_repeat_counter %d",
          //            byte_counter, pixel_shift_reg, video, vertical_pixel_counter, horizontal_pixel_counter, line_repeat_counter);  
          
          video <= pixel_shift_reg[7];
          pixel_shift_reg <= pixel_shift_reg << 1;

          nbit <= nbit + 1'd1;
          if (nbit == 8'd7) begin
            nbit <= 8'd0;
            load_byte <= 1;
            byte_counter <= byte_counter + 1'd1;         
          end      
          horizontal_counter <= horizontal_counter + 1'd1;
          horizontal_pixel_counter <= horizontal_pixel_counter + 1'd1;

          if(byte_counter == 8) begin
            byte_counter <= 0;

            // repeat 4 times, then move on to next row
            if (line_repeat_counter == 3'd3) begin
              line_repeat_counter <= 3'd0;
              video_state <= SM_READ_ROW;
            end
            else begin
              line_repeat_counter <= line_repeat_counter + 1'd1; 
              vertical_counter <= vertical_counter + 1'd1;    
              vertical_pixel_counter <= vertical_pixel_counter + 1'd1;  
            end

          end
        end
      end
    endcase 
  end

  // Create HSync and HBlank
  HSync <= (horizontal_pixel_counter <= (hsync_start_pixel+hsync_width_pixels)) ? 1'b1 : 1'b0;  
  HBlank <= (horizontal_pixel_counter < 16 || horizontal_pixel_counter > 80)  ? 1'b1 : 1'b0;  // 64 pixels wide
  //$display("HSync %h HBlank %h horizontal_pixel_counter %d", HSync, HBlank, horizontal_pixel_counter);

  // Create VSync and VBlank
  VSync <= (vertical_pixel_counter <= (vsync_start_line+vsync_height_lines)) ? 1'b1 : 1'b0;
  VBlank <= (vertical_pixel_counter < 64 || vertical_pixel_counter > 192) ? 1'b1 : 1'b0;  // 128 lines for NTSC  
  //$display("VSync %h VBlank %h vertical_pixel_counter   %d", VSync, VBlank, vertical_pixel_counter);

  EFx <= ((vertical_pixel_counter > 60 && vertical_pixel_counter < 65) || (vertical_pixel_counter > 192 && vertical_pixel_counter < 194)) ? 1'b0 : 1'b1;  // TODO check again
  INT <= (vertical_pixel_counter == 62) ? 1'b1 : 1'b0;  // TODO check again

  if (VBlank) begin
    halt_vertical_pixel_counter <= 1'b0;
  end
  if (HBlank) begin
    halt_horizontal_pixel_counter <= 1'b0;
  end

end

endmodule
