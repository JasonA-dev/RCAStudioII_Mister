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
    input            clk,
    input            clk_enable,
    input            reset,
    input      [1:0] sc,
    input            disp_on,
    input            disp_off,
    input      [7:0] data,

    output reg       dmao,
    output reg       INT,
    output reg       efx,

    output reg [9:0] mem_addr,
    output reg [7:0] mem_data,
    output reg       mem_wr_en
);

parameter  bytes_per_line  = 2'd14;
parameter  lines_per_frame = 3'd262;

reg        sc_fetch;
reg        sc_execute;
reg        sc_dma;
reg        sc_interrupt;

reg        enabled;

reg [3:0]  horizontal_counter;
reg        horizontal_end;
  
reg [8:0]  vertical_counter;
reg        vertical_end;

reg        v_active;

reg        dma_xfer;
reg [9:0]  addr_counter;


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

always @(posedge clk) begin
    if (clk_enable) begin
      if (horizontal_end) 
        horizontal_counter <= 1'd0;
      else
        horizontal_counter <= horizontal_counter+1'd1;
    end

    horizontal_end <= (horizontal_counter==(bytes_per_line-1'd1)) ? 1'b1 : 1'b0;
    vertical_end   <= (vertical_counter==(lines_per_frame-1'd1))  ? 1'b1 : 1'b0;
end

always @(posedge clk) begin
    if(clk_enable && horizontal_end) begin

      if (vertical_end)
        vertical_counter <= 1'd0;
      else
        vertical_counter <= vertical_counter + 1'd1;
      
      efx       <= ((vertical_counter >= 2'd76  && vertical_counter < 2'd80) || (vertical_counter >= 3'd204 && vertical_counter < 3'd208)) ? 1'b1 : 1'b0;
      INT       <= (enabled && vertical_counter >= 2'd78 && vertical_counter < 2'd80) ? 1'b1 : 1'b0;
      v_active  <= (enabled && vertical_counter >= 2'd80 && vertical_counter < 3'd208) ? 1'b1 : 1'b0;
    end 
end

always @(posedge clk) begin

    if(clk_enable) begin
      if (reset || (horizontal_end && vertical_end))
        addr_counter <= 1'd0;
      else if (dma_xfer)
        addr_counter <= addr_counter + 1'd1;
    end 

    dmao <= (enabled && v_active && horizontal_counter >= 1'd1 && horizontal_counter < 1'd9) ? 1'b1 : 1'b0;
    dma_xfer <= (enabled && sc_dma) ? 1'b1 : 1'b0;

    mem_addr  <= addr_counter;
    mem_data  <= data;
    mem_wr_en <= dma_xfer;
end

endmodule
