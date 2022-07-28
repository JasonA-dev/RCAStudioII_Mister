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

module pixie_video
(
    // backend
    input              clk,
    input              reset, 

    output             csync,
    output  reg        video,

    output             VSync,
    output             HSync,    
    output             VBlank,
    output             HBlank,
    output             video_de,      

    // frontend
    input             clk_enable,
    input       [1:0] SC,
    input             disp_on,
    input             disp_off,
    input       [7:0] data_in,

    output reg        DMAO,
    output reg        INT,
    output reg        EFx,

    output reg  [15:0] mem_addr,
    output reg        mem_wr_en
);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

parameter  pixels_per_line    = 112; // (14bytes x 8bits, constant for all 1861's)
parameter  bytes_per_line     = 14;
parameter  active_h_pixels    = 64;  // (studio2 has 64 active pixels per visible horizontal row) 
parameter  hsync_start_pixel  = 2;   // two cycles later to account for pipeline delay
parameter  hsync_width_pixels = 12;  

parameter  lines_per_frame    = 262; // (constant for all 1861's) 
parameter  active_v_lines     = 128; // (NTSC (PAL is 192. There is no PAL natively on StudioII))
parameter  vsync_start_line   = 2;  
parameter  vsync_height_lines = 6;  

parameter  start_addr         = 'h0900;
parameter  end_addr           = start_addr + 'hff;

//PAL
// interruptGraphicsMode_ = 74;
// startGraphicsMode_ = 76;
// endGraphicsMode_ = 267;
// endScreen_ = 312;
// videoHeight_ = 192;

//NTSC
// interruptGraphicsMode_ = 62;
// startGraphicsMode_ = 64;
// endGraphicsMode_ = 191;
// endScreen_ = 262;
// videoHeight_ = 128;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

reg  [7:0] pixel_shift_reg;
  
reg  [7:0] horizontal_counter;
reg        hsync;
reg        advance_v;
    
reg  [8:0] vertical_counter;
reg        vsync;

reg  [8:0] new_v;
reg  [7:0] new_h;

reg        SC_fetch;
reg        SC_execute;
reg        SC_dma;
reg        SC_interrupt;

reg        enabled;

reg        DMA_xfer;
reg  [9:0] addr_counter;

reg  [7:0] byte_cache[8];
reg  [7:0] byte_counter = 0;
reg  [7:0] row_counter;
reg  [7:0] cycle_counter;
reg  [15:0] vram_addr = start_addr;
reg        advance_addr;

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

// new vram data loader
always @(negedge clk) begin
  if(advance_addr==1'b1) begin

    if(vram_addr < end_addr) begin
      vram_addr <= vram_addr + 1'd1;
    end
    else
      vram_addr <= start_addr;
  end  
  mem_addr <= vram_addr;    
end

// new horizontal counter
always @(negedge clk) begin
  if (horizontal_counter == (pixels_per_line-1)) begin
    new_h <= 1'd0;
    advance_v <= 1'b1;
  end
  else begin
    new_h <= horizontal_counter + 1'd1;
  end

  if(horizontal_counter[2:0]== 3'b000 && HBlank==1'b0) begin
    advance_addr <= 1'b1;
    byte_cache[byte_counter] <= data_in;
    byte_counter <= byte_counter + 1'b1;    
    if(byte_counter==7) begin
      byte_counter <= 0;
    end       
  end

  horizontal_counter <= new_h;
  HSync <= (new_h < (hsync_start_pixel+hsync_width_pixels)) ? 1'b1 : 1'b0;  
  HBlank <= (horizontal_counter < 18 || horizontal_counter > 82)  ? 1'b1 : 1'b0;  // 64 pixels wide
end

// new vertical counter
always @(posedge clk) begin
  if(advance_v) begin
    advance_v <= 0;
    if (vertical_counter==(lines_per_frame-1))
      new_v <= 1'd0;
    else
      new_v <= vertical_counter + 1'b1;
    vertical_counter <= new_v;
  end

  VSync <= (new_v < (vsync_start_line+vsync_height_lines)) ? 1'b1 : 1'b0;
  VBlank <= (vertical_counter   < 64 || vertical_counter   > 192) ? 1'b1 : 1'b0;  // 128 lines for NTSC  
end

always @(posedge clk) begin
    if(clk_enable) begin
      EFx <= ((vertical_counter >=60 && vertical_counter < 65) || (vertical_counter >= 188 && vertical_counter < 193)) ? 1'b0 : 1'b1;  // OK
      INT <= (vertical_counter == 62)  ? 1'b1 : 1'b0;
    end
end

//pixel_shifter_p
always @(negedge clk) begin

  if(advance_addr==1'b1) begin
    pixel_shift_reg <= byte_cache[0];
    advance_addr <= 0;
    //$display("pixel_shift_reg: %h byte_cache[byte_counter] %h byte_counter %h", pixel_shift_reg, byte_cache[byte_counter], byte_counter);
  end

  pixel_shift_reg <= {pixel_shift_reg[6:0], 1'b0};

 // if(video_de) begin
 //   video <= pixel_shift_reg[7];   
 // end   
end

always @(negedge clk) begin
    video <= pixel_shift_reg[7];   
 // $display("byte_cache[byte_counter] %h byte_counter %h", byte_cache[byte_counter], byte_counter);
 
end

endmodule
