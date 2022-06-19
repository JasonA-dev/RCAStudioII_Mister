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

module pixie_dp_back_end
(
    input         clk,
    output  reg      fb_read_en,
    output  [9:0] fb_addr,
    input   [7:0] fb_data,
    output        csync,
    output  reg      video,

    output        VSync,
    output        HSync,    
    output        VBlank,
    output        HBlank,
    output        video_de      
);

wire pixels_per_line    = 3'd112;
wire active_h_pixels    = 2'd64;
wire hsync_start_pixel  = 2'd82;  // two cycles later to account for pipeline delay
wire hsync_width_pixels = 2'd12;

wire lines_per_frame    = 3'd262;
wire active_v_lines     = 3'd128;
wire vsync_start_line   = 3'd182;
wire vsync_height_lines = 2'd16;

reg        load_pixel_shift_reg;
reg [7:0]  pixel_shift_reg;
  
reg [7:0]  horizontal_counter;
reg        hsync;
reg        active_h_adv2;  // pipeline delay
reg        active_h_adv1;  // pipeline delay
reg        active_h;
reg        advance_v;
    
reg   [8:0] vertical_counter;
reg        vsync;
reg        active_v;
  
wire        active_video;


assign VSync = vsync;
assign HSync = hsync;
assign video_de = active_video;
assign VBlank = vertical_counter > 79;
assign HBlank = horizontal_counter > 28;

assign fb_addr[9:3] = vertical_counter[6:0];
assign fb_addr[2:0] = horizontal_counter[5:3];

reg [2:0] new_v;
reg [2:0] new_h;

// horizontal_counter_p     
always @(posedge clk) begin

    if (horizontal_counter == (pixels_per_line-1'd1)) 
        new_h <= 1'd0;
    else
        new_h <= horizontal_counter + 1'd1;

    horizontal_counter <= new_h;

    fb_read_en <= (new_h[2:0]==3'b000) ? 1'b1 : 1'b0;
    load_pixel_shift_reg <= (new_h[2:0]==3'b001) ? 1'b1 : 1'b0;
    active_h_adv2 <= (new_h<active_h_pixels) ? 1'b1 : 1'b0;

    active_h_adv1 <= active_h_adv2;
    active_h      <= active_h_adv1;

    hsync <= (new_h>=hsync_start_pixel && new_h<hsync_start_pixel+hsync_width_pixels) ? 1'b1 : 1'b0;
    advance_v <= new_h==(pixels_per_line-1'd1) ? 1'b1 : 1'b0;

end

//vertical_counter_p
always @(posedge clk) begin
    if (advance_v==1'b1) begin

      if (vertical_counter==(lines_per_frame-1))
        new_v <= 1'd0;
      else
        new_v <= vertical_counter + 1'd1;

      vertical_counter <= new_v;
      active_v <= (new_v<active_v_lines) ? 1'b1 : 1'b0;
      vsync <= (new_v>=vsync_start_line && new_v<vsync_start_line+vsync_height_lines) ? 1'b1 : 1'b0;
    
    end
end

assign csync = hsync ^ vsync;
assign active_video = active_h & active_v;

//pixel_shifter_p
always @(posedge clk) begin

    if (load_pixel_shift_reg==1'b1)
        pixel_shift_reg <= fb_data;
    else
        pixel_shift_reg <= {pixel_shift_reg[6:0], 1'b0};

    video <= active_video & pixel_shift_reg[7];
end

endmodule