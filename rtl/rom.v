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

//-------------------------------------------------------------------------------------------------
module rom
//-------------------------------------------------------------------------------------------------
#
(
	parameter DW = 8,
	parameter AW = 14,
	parameter FN = ""
)
(
	input  wire         clock,
	input  wire         ce,
	output reg [DW-1:0] data_out,
	input  wire[AW-1:0] a
);
//-------------------------------------------------------------------------------------------------

reg[DW-1:0] d[(2**AW)-1:0];

initial $readmemh(FN, d, 0);

always @(posedge clock) if(ce) data_out<= d[a];

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------