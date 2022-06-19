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

module pixie_dp_front_end 
(
    input        clk,
    input        clk_enable,
    input        reset,
    input  [1:0] sc,
    input        disp_on,
    input        disp_off,
    input  [7:0] data,

    output       dmao,
    output       int,
    output       efx,

    output [9:0] mem_addr,
    output [7:0] mem_data,
    output       mem_wr_en
);

reg         bytes_per_line  = 'd14;
reg         lines_per_frame = 'd262;

wire        sc_fetch;
wire        sc_execute;
wire        sc_dma;
wire        sc_interrupt;

wire        enabled;

wire [3:0]  horizontal_counter;
wire        horizontal_end;
  
wire [8:0]  vertical_counter;
wire        vertical_end;

wire        v_active;

wire        dma_xfer;
wire [9:0]  addr_counter;


always @(posedge clk) begin
    case (sc)
      2'b00: sc_fetch     <= 1'b1;
      2'b01: sc_execute   <= 1'b1;
      2'b10: sc_dma       <= 1'b1;
      2'b11: sc_interrupt <= 1'b1;                  
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

horizontal_end <= (horizontal_counter==(bytes_per_line-1);

always @(posedge clk) begin
    if (clk_enable) begin
      if (horizontal_end) 
        horizontal_counter <= 'd0;
      else
        horizontal_counter <= horizontal_counter + 1'd1;
    end
end

vertical_end <= (vertical_counter==(lines_per_frame-1));

always @(posedge clk) begin
    if(clk_enable && horizontal_end) begin

      if (vertical_end)
        vertical_counter <= 'd0;
      else
        vertical_counter <= vertical_counter + 1'd1;
      
      efx       <= ((vertical_counter >= 76  && vertical_counter < 80) || (vertical_counter >= 204 && vertical_counter < 208));
      int       <= (enabled && vertical_counter >= 78 && vertical_counter < 80);
      v_active  <= (enabled && vertical_counter >= 80 && vertical_counter < 208);
    end 
end

dmao <= (enabled && v_active && horizontal_counter >= 1 && horizontal_counter < 9);
dma_xfer <= (enabled && sc_dma == '1');

always @(posedge clk) begin
    if(clk_enable) begin
      if (reset || (horizontal_end && vertical_end)
        addr_counter <= 'd0;
      else if (dma_xfer)
        addr_counter <= addr_counter + 1;
    end 
end


mem_addr  <= addr_counter;
mem_data  <= data;
mem_wr_en <= dma_xfer;

endmodule