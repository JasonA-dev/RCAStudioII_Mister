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
    output  wire        video,

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

    output reg  [15:0] mem_addr,
    input              mem_ack    
);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

parameter  pixels_per_line    = 112; // (14 bytes x 8bits, constant for all 1861's)
parameter  bytes_per_line     = 14;  // 
parameter  active_h_pixels    = 64;  // (studio2 has 64 active pixels per visible horizontal row) 
parameter  hsync_start_pixel  = 2;   // two cycles later to account for pipeline delay
parameter  hsync_width_pixels = 6;   // 12

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
 // if(mem_ack) begin
    frame_buffer[fb_addr-2] <= data_in;    
    fb_addr <= vram_addr-start_addr;
    mem_addr <= vram_addr;      
    vram_addr <= vram_addr + 1;   

    if (vram_addr == end_addr) begin
      vram_addr <= start_addr;
    end               
 // end
end

// Video State Machine constants
localparam SM_READ_ROW = 0;
localparam SM_GENERATE_PIXELS = 1;
reg [7:0] video_state = SM_READ_ROW;

reg [15:0] video_byte_counter = 0;
reg  [7:0] byte_counter = 0;

always @(posedge clk) begin
    case (video_state)
      SM_READ_ROW: begin
        row_cache[row_cache_counter] <= frame_buffer[row_cache_counter+video_byte_counter];
        // $display("SM_READ_ROW row_cache_counter %d video_byte_counter %d row_cache[row_cache_counter] %h", row_cache_counter, video_byte_counter, row_cache[row_cache_counter]); 
        if (row_cache_counter == 7) begin
          row_cache_counter <= 0;
          video_byte_counter <= video_byte_counter + 8;    
          video_state <= SM_GENERATE_PIXELS;                 
        end  
        else begin
          row_cache_counter <= row_cache_counter + 1;  
        end

        if (video_byte_counter == 256) begin
          video_byte_counter <= 0;
        end    
      end

      SM_GENERATE_PIXELS: begin
        if(load_byte) begin
          pixel_shift_reg <= row_cache[byte_counter];
          load_byte <= 0;
          // $display("SM_GENERATE_PIXELS load_byte byte_counter %d pixel_shift_reg %h row_cache[byte_counter] %h", byte_counter, pixel_shift_reg, row_cache[byte_counter]);               
        end
        else begin
          //video <= pixel_shift_reg[7];
          // $display("SM_GENERATE_PIXELS byte_counter %d pixel_shift_reg %h video %h", byte_counter, pixel_shift_reg, video);    
          pixel_shift_reg <= pixel_shift_reg << 1;

          nbit <= nbit + 1'd1;
          if (nbit == 8'd7) begin
            nbit <= 8'd0;
            load_byte <= 1;
            byte_counter <= byte_counter + 1;          
          end      
          new_h <= horizontal_counter + 1'd1;

          if(byte_counter == 8) begin
            byte_counter <= 0;
            video_byte_counter <= video_byte_counter + 8;

            // repeat 4 times, then move on to next row
            if (line_repeat_counter == 3'd3) begin
              line_repeat_counter <= 3'd0;
              video_state <= SM_READ_ROW;
            end
            else begin
              line_repeat_counter <= line_repeat_counter + 1;
              new_v <= vertical_counter + 1'd1;      
            end
          end
        end
      end
    endcase 

  // Create HSync and HBlank
  if (horizontal_counter == (pixels_per_line)) begin
    new_h <= 1'd0;
    advance_v <= 1'b1;
  end
  horizontal_counter <= new_h;
  HSync <= (new_h < (hsync_start_pixel+hsync_width_pixels)) ? 1'b1 : 1'b0;  
  HBlank <= (new_h < 16 || new_h > 80)  ? 1'b1 : 1'b0;  // 64 pixels wide
  // $display("horizontal_counter %d HSync %h HBlank %h", horizontal_counter, HSync, HBlank);

  // Create VSync and VBlank
  if(advance_v) begin
    advance_v <= 1'b0;
    if (vertical_counter==(lines_per_frame)) begin
      new_v <= 1'd0;
    end
    vertical_counter <= new_v;
  end
  VSync <= (new_v < (vsync_start_line+vsync_height_lines)) ? 1'b1 : 1'b0;
  VBlank <= (new_v < 64 || new_v > 192) ? 1'b1 : 1'b0;  // 128 lines for NTSC  
  // $display("vertical_counter %d VSync %h VBlank %h", vertical_counter, VSync, VBlank);

  EFx <= ((new_v >=60 && new_v < 65) || (new_v > 192 && new_v < 194)) ? 1'b0 : 1'b1;  // TODO check again
  INT <= (new_v == 62) ? 1'b1 : 1'b0;  // TODO check again
end

assign video = pixel_shift_reg[7];

endmodule
