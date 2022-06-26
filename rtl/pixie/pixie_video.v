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

    output  reg        fb_read_en,
    output       [9:0] fb_addr,
    input        [7:0] fb_data,
    output             csync,
    output  reg        video,

    output             VSync,
    output             HSync,    
    output             VBlank,
    output             HBlank,
    output             video_de,      

    // frontend
    input            clk_enable,
    input      [1:0] SC,
    input            disp_on,
    input            disp_off,
    input      [7:0] data_in,

    output reg       DMAO,
    output reg       INT,
    output reg       EFx,

    output reg [9:0] mem_addr,
    output reg [7:0] mem_data,
    output reg       mem_wr_en
);

// backend
parameter  pixels_per_line    = 112; // (14bytes x 8bits, constant for all 1861's)
parameter  active_h_pixels    = 64;  // (studio2 has 64 active pixels per visible horizontal row) 
parameter  hsync_start_pixel  = 2;   // two cycles later to account for pipeline delay
parameter  hsync_width_pixels = 1;  

parameter  lines_per_frame    = 262; // (constant for all 1861's) 
parameter  active_v_lines     = 128; // (NTSC (PAL is 192. There is no PAL natively on StudioII))
parameter  vsync_start_line   = 2;  
parameter  vsync_height_lines = 1;  

reg        load_pixel_shift_reg;
reg  [7:0] pixel_shift_reg;
  
reg  [7:0] horizontal_counter;
reg        hsync;
reg        active_h;
reg        advance_v;
    
reg  [8:0] vertical_counter;
reg        vsync;
reg        active_v;
  
wire       active_video;

assign VSync    = vsync;
assign HSync    = hsync;
assign video_de = active_video;
//assign VBlank   = (vertical_counter   < 64 && vertical_counter   > 192);    // 128 lines for NTSC
//assign HBlank   = (horizontal_counter < 18 && horizontal_counter > 82);     // 64 pixels wide

reg [8:0] new_v;
reg [7:0] new_h;

// frontend 
parameter  bytes_per_line  = 14;

reg        SC_fetch;
reg        SC_execute;
reg        SC_dma;
reg        SC_interrupt;

reg        enabled;

reg        horizontal_end;
reg        vertical_end;

reg        v_active;

reg        DMA_xfer;
reg [9:0]  addr_counter;

//////////////////////////////////////////////////////////////////////////////////////////////

parameter start_addr = 'h0900;
parameter end_addr = start_addr + 'h1ff;
reg [7:0] byte_cache[8];
reg [7:0] byte_counter;
reg [7:0] row_counter;
reg [7:0] cycle_counter;
reg [7:0] vram_addr = start_addr;
reg       advance_addr;

// new vram data loader
always @(posedge clk) begin
  if(advance_addr==1'b1) begin
    advance_addr <= 0;
    if(vram_addr < end_addr) 
      vram_addr <= vram_addr + 1'd1;
    else 
      vram_addr <= start_addr;   

    fb_addr <= vram_addr; 
  end    
  
  VBlank <= (vertical_counter   < 64 || vertical_counter   > 192) ? 1'b1 : 1'b0;  // 128 lines for NTSC
  HBlank <= (horizontal_counter < 18 || horizontal_counter > 82)  ? 1'b1 : 1'b0;  // 64 pixels wide

end

// new vertical counter
always @(posedge clk) begin
  if(advance_v) begin
    advance_v <= 0;
    if (vertical_counter==(lines_per_frame-1))
      new_v <= 1'd0;
    else
      new_v <= vertical_counter + 1'd1;

    vertical_counter <= new_v;
    $display("vertical_counter: %h new_v: %h", vertical_counter, new_v);  
  end
end
// new horizontal counter
always @(negedge clk) begin
  if (horizontal_counter == (pixels_per_line-1)) begin
    new_h <= 1'd0;
    advance_v <= 1'b1;
  end
  else
    new_h <= horizontal_counter + 1'd1;

  if(horizontal_counter[2:0]== 3'b000 && HBlank==1'b0) begin
    advance_addr <= 1'b1;
    $display("new_h[2:0]== 3'b000 advance_addr: %h, vram_addr %h HBlank %h", advance_addr, vram_addr, HBlank);
  end

  horizontal_counter <= new_h;
  $display("horizontal_counter: %h new_h: %h", horizontal_counter, new_h);
end

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// horizontal_counter_p     
always @(posedge clk) begin

    if (horizontal_counter == (pixels_per_line-1)) begin
        new_h <= 1'd0;
    end
    else
        new_h <= horizontal_counter + 1'd1;

    horizontal_counter <= new_h;

    fb_read_en           <= (new_h[2:0]==3'b000)    ? 1'b1 : 1'b0;
    load_pixel_shift_reg <= (new_h[2:0]==3'b001)    ? 1'b1 : 1'b0;
    active_h             <= (new_h<active_h_pixels) ? 1'b1 : 1'b0;

    hsync     <= ((new_h>=hsync_start_pixel) && (new_h<hsync_start_pixel+hsync_width_pixels)) ? 1'b1 : 1'b0;
    advance_v <= (new_h==(pixels_per_line-1'd1)) ? 1'b1 : 1'b0;
end

//vertical_counter_p
always @(posedge clk) begin
    if (advance_v) begin

      if (vertical_counter==(lines_per_frame-1))
        new_v <= 1'd0;
      else
        new_v <= vertical_counter + 1'd1;

      vertical_counter <= new_v;

      active_v <= (new_v<active_v_lines) ? 1'b1 : 1'b0;
      vsync <= ((new_v>=vsync_start_line) && (new_v<vsync_start_line+vsync_height_lines)) ? 1'b1 : 1'b0;
    
    end
end

assign csync = ~(hsync ^ vsync);
assign active_video = active_h && active_v;

//pixel_shifter_p
always @(posedge clk) begin

    if (load_pixel_shift_reg==1'b1) 
        pixel_shift_reg <= fb_data;
    else if (reset)
        pixel_shift_reg <= 0;
    else 
        pixel_shift_reg <= {pixel_shift_reg[6:0], 1'b0};        
    
    if(active_video)
        video <= pixel_shift_reg[7];   
end

/////////////////////////frontend /////////////////////////////////////////////////////////////////////////////////

always @(posedge clk) begin
    case (SC)
      2'b00: SC_fetch     <= 1'b1;
      2'b01: SC_execute   <= 1'b1;
      2'b10: SC_dma       <= 1'b1;
      2'b11: SC_interrupt <= 1'b1;                  
    endcase
end

always @(posedge clk) begin
    if (clk_enable) begin
      if(reset)
        enabled <= 1'b0;
      else if (disp_on)
        enabled <= 1'b1;
      else if (disp_off)
        enabled <= 1'b0;
    end
end

always @(posedge clk) begin
    if (clk_enable) begin
      if (horizontal_end) 
        horizontal_counter <= 0;
      else
        horizontal_counter <= horizontal_counter+1;
    end
    horizontal_end <= horizontal_counter==bytes_per_line-1  ? 1'b1 : 1'b0;
    vertical_end   <= vertical_counter  ==lines_per_frame-1 ? 1'b1 : 1'b0;
end

always @(posedge clk) begin
    if(clk_enable && horizontal_end) begin
      if (vertical_end)
        vertical_counter <= 0;
      else
        vertical_counter <= vertical_counter + 1;
      
      EFx       <= ((vertical_counter >=60 && vertical_counter < 65) || (vertical_counter >= 188 && vertical_counter < 193)) ? 1'b0 : 1'b1;
      INT       <= (enabled && vertical_counter >= 260 && vertical_counter < 262)  ? 1'b1 : 1'b0;
      v_active  <= (enabled && vertical_counter >= 108 && vertical_counter < 112) ? 1'b1 : 1'b0;
    end
end

assign DMAO     = (enabled && v_active && horizontal_counter >= 1 && horizontal_counter < 9) ? 1'b0 : 1'b1;
assign DMA_xfer = (enabled && SC_dma) ? 1'b1 : 1'b0;

always @(posedge clk) begin
    if(clk_enable) begin
      if (reset || (horizontal_end && vertical_end))
        addr_counter <= 1'd0;
      else if (DMA_xfer)
        addr_counter <= addr_counter + 1'd1;
    end 
end

assign mem_addr  = addr_counter;
assign mem_data  = data_in;
assign mem_wr_en = DMA_xfer;

endmodule
