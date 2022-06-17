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

module dma (

  input             clk, 
  input             rdy,
  input       [7:0] ctrl,
  input      [15:0] src_addr,
  input      [15:0] dst_addr,
  output reg [15:0] addr,
  input       [7:0] din,
  output reg  [7:0] dout,
  input       [7:0] length,
  output            busy,
  output            sel, // 1: src -> dst, 2: src <- dst
  output            write
);

reg [11:0] queue;
reg [12:0] addr_a, addr_b;
reg        started;

assign sel   = dst_addr[14];
assign busy  = state != DONE;
assign write = state == WRITE;
reg [1:0] state;

parameter
  DONE  = 2'b00,
  START = 2'b01,
  READ  = 2'b10,
  WRITE = 2'b11;

always @(posedge clk)
  started <= ctrl[7] ? 1'b1 : 1'b0;

always @(posedge clk)
  if (rdy)
    case (state)
      DONE: if (~started & ctrl[7]) state <= START;
      START: state <= READ;
      READ: state <= WRITE;
      WRITE: state <= queue == 0 ? DONE : READ;
    endcase

always @(posedge clk)
  if (rdy)
    case (state)
      START: queue <= { length, 4'd0 };
      WRITE: queue <= queue - 12'b1;
    endcase

always @(posedge clk)
  if (rdy)
    case (state)
      READ: addr <= addr_a;
      WRITE: addr <= addr_b;
    endcase

always @(posedge clk)
  if (rdy && state == WRITE) dout <= din;

always @(posedge clk)
  if (rdy)
    case (state)
      START: begin
        addr_a <= sel ? src_addr[12:0] : dst_addr[12:0];
        addr_b <= sel ? dst_addr[12:0] : src_addr[12:0];
      end
      WRITE: begin
        addr_a <= addr_a + 13'b1;
        addr_b <= addr_b + 13'b1;
      end
    endcase

endmodule
