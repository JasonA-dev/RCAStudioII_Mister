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
    output        fb_read_en,
    output  [9:0] fb_addr,
    input   [7:0] fb_data,
    output        csync,
    output        video
);

wire pixels_per_line    = 'd112;
wire active_h_pixels    = 'd64;
wire hsync_start_pixel  = 'd82;  // two cycles later to account for pipeline delay
wire hsync_width_pixels = 'd12;

wire lines_per_frame    = 'd262;
wire active_v_lines     = 'd128;
wire vsync_start_line   = 'd182;
wire vsync_height_lines = 'd16;

wire        load_pixel_shift_reg;
wire [7:0]  pixel_shift_reg;
  
wire [7:0]  horizontal_counter;
wire        hsync;
wire        active_h_adv2;  // pipeline delay
wire        active_h_adv1;  // pipeline delay
wire        active_h;
wire        advance_v;
    
reg   [8:0] vertical_counter;
wire        vsync;
wire        active_v;
  
wire        active_video;

fb_addr[9:3] = vertical_counter[6:0];
fb_addr[2:0] = horizontal_counter[5:3];

// horizontal_counter_p     
always @(posedge clk) begin

    if (horizontal_counter == (pixels_per_line - 1)) 
        new_h <= {0, horizontal_counter'length};
    else
        new_h <= horizontal_counter + 1'd1;

    horizontal_counter <= new_h;

    fb_read_en <= new_h[2:0]=="000";
    load_pixel_shift_reg <= new_h[2:0]=="001";
    active_h_adv2 <= new_h < active_h_pixels;

    active_h_adv1 <= active_h_adv2;
    active_h      <= active_h_adv1;

    hsync <= new_h>=hsync_start_pixel && new_h<hsync_start_pixel+hsync_width_pixels;
    advance_v <= new_h==(pixels_per_line-1);

end

//vertical_counter_p
always @(posedge clk) begin
    if (advance_v==1'b1) begin

      if (vertical_counter==(lines_per_frame-1))
        new_v <= {0, vertical_counter'length};
      else
        new_v <= vertical_counter + 1'd1;

      vertical_counter <= new_v;
      active_v <= (new_v<active_v_lines);
      vsync <= (new_v>=vsync_start_line && new_v<vsync_start_line+vsync_height_lines);
    
    end
end

csync <= hsync ^ vsync;
active_video <= active_h & active_v;

//pixel_shifter_p
always @(posedge clk) begin

    if (load_pixel_shift_reg==1'b1)
        pixel_shift_reg <= fb_data;
    else
        pixel_shift_reg <= {pixel_shift_reg[6:0], 0};

    video <= active_video & pixel_shift_reg[7];
end

endmodule