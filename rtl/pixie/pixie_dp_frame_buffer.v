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

module pixie_dp_frame_buffer 
(
    input            clk_a,
    input            en_a,
    input      [9:0] addr_a,
    input      [7:0] d_in_a,

    input            clk_b,
    input            en_b,
    input      [9:0] addr_b,
    output reg [7:0] d_out_b
);

reg [7:0] ram[4096];

always @(posedge clk_a) begin
  if (en_a) begin
    //$display("addr_a %x: d_in_a %x", addr_a, d_in_a);
    ram[addr_a] <= d_in_a;
  end
end

always @(posedge clk_b) begin
  if (en_b)
    d_out_b <= ram[addr_b];
end

endmodule