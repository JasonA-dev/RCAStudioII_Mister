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

//`timescale 1ns / 1ps

module bram (
  input clk,

  input bram_download,
  input bram_wr,
  input [15:0] bram_init_address,
  input [7:0] bram_din,

  input cs,
  input [15:0] addr,
  output reg [7:0] dout
);

reg [7:0] memory[512:0];

always @(posedge clk) begin
  if (bram_download && bram_wr)
    memory[bram_init_address] <= bram_din;
  else if (cs)
    dout <= memory[addr];
end

endmodule