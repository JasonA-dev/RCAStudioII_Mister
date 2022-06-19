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

module pixie_dp 
(
    // front end, CDP1802 bus clock domain
    input         clk,
    input         reset,  
    input         clk_enable,

    input   [1:0] sc,         
    input         disp_on,
    input         disp_off,
    input   [7:0] data,     

    output        dmao,     
    output        INT,     
    output        efx,

    // back end, video clock domain
    input         video_clk,
    output        csync,     
    output        video,

    output        VSync,
    output        HSync,    
    output        VBlank,
    output        HBlank,
    output        video_de  
);

reg   [9:0] fb_a_addr;
reg   [7:0] fb_a_data;
wire        fb_a_en;

wire        fb_a_en2;

reg   [9:0] fb_b_addr;
reg   [7:0] fb_b_data;
wire        fb_b_en;

pixie_dp_front_end pixie_dp_front_end (
    .clk        (clk),
    .clk_enable (clk_enable),
    .reset      (reset),
    .sc         (sc),
    .disp_on    (disp_on),
    .disp_off   (disp_off),
    .data       (data),

    .dmao       (dmao),
    .INT        (INT),
    .efx        (efx),

    .mem_addr   (fb_a_addr),
    .mem_data   (fb_a_data),
    .mem_wr_en  (fb_a_en)
);

assign fb_a_en2 = (clk_enable & fb_a_en);

pixie_dp_frame_buffer pixie_dp_frame_buffer (
    .clk_a    (clk),
    .en_a     (fb_a_en2),
    .addr_a   (fb_a_addr),
    .d_in_a   (fb_a_data),

    .clk_b    (video_clk),
    .en_b     (fb_b_en),
    .addr_b   (fb_b_addr),
    .d_out_b  (fb_b_data)
);

pixie_dp_back_end pixie_dp_back_end (
    .clk        (video_clk),
    .fb_read_en (fb_b_en),
    .fb_addr    (fb_b_addr),
    .fb_data    (fb_b_data),

    .csync      (csync),
    .video      (video),

    .VSync      (VSync),
    .HSync      (HSync),    
    .VBlank     (VBlank),
    .HBlank     (HBlank),
    .video_de   (video_de)  
);

endmodule
