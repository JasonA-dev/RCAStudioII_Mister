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
    // front end, CDP1802 bus clock domain
    input             clk,
    input             reset,  
    input             clk_enable,

    input       [1:0] SC,         
    input             disp_on,
    input             disp_off,

    input       [7:0] data_in,     
    output wire [15:0] data_addr,

    output            DMAO,     
    output            INT,     
    output            EFx,

    // back end, video clock domain
    input             video_clk,
    output            csync,     
    output            video,

    output            VSync,
    output            HSync,    
    output            VBlank,
    output            HBlank,
    output            video_de  
);

// RCA Studio II
pixie_video_studioii pixie_video_studioii (
    .clk        (video_clk),    // I
    .reset      (reset),        // I

    .csync      (csync),        // O
    .video      (video),        // O

    .VSync      (VSync),        // O
    .HSync      (HSync),        // O  
    .VBlank     (VBlank),       // O
    .HBlank     (HBlank),       // O
    .video_de   (video_de),     // O

    // frontend
    .clk_enable (clk_enable),   // I
    .SC         (SC),           // I [1:0]
    .disp_on    (disp_on),      // I
    .disp_off   (disp_off),     // I
    .data_in    (data_in),      // I [7:0]

    .DMAO       (DMAO),         // O
    .INT        (INT),          // O
    .EFx        (EFx),          // O

    .mem_addr   (data_addr)     // O [9:0]
);

endmodule
