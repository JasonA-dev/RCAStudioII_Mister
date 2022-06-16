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
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module rcastudioii
(
	input         clk,
	input         reset,
	
	input         pal,
	input         scandouble,

	output reg    ce_pix,

	output reg    HBlank,
	output reg    HSync,
	output reg    VBlank,
	output reg    VSync,

	output  [7:0] video
);

cdp1861 cdp1861 (

    .clock(clk),
    .Reset_(),
    
    .Disp_On(),
    .Disp_Off(),
    .TPA(),
    .TPB(),
    .SC(),
    .DataIn(),

    .Clear(),
    .INT(),
    .DMAO(),
    .EFx(),

    .Video(video),
    .CompSync_(),
    .Locked()
);

wire[ 7:0] romDo_StudioII;
wire[11:0] romA;

rom #(.AW(11), .FN("../rom/studio2.hex")) Rom_StudioII
(
	.clock      (clk            ),
	.ce         (1'b1           ),
	.data_out   (romDo_StudioII ),
	.a          (romA[10:0]     )
);

bram ram (
  .clk(clk),

  .bram_download(),
  .bram_wr(),
  .bram_init_address(),
  .bram_din(),

  .cs(),
  .addr(),
  .dout()
);

endmodule
