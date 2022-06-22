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
    input      [1:0] SC,
    input            disp_on,
    input            disp_off,
    input      [7:0] data_in,

    output reg       DMAO,
    output reg       INT,
    output reg       EFx,

    output reg [9:0] mem_addr,
    output reg [7:0] mem_data,
    output reg       mem_wr_en
);

parameter  bytes_per_line  = 14;
parameter  lines_per_frame = 262;

reg        SC_fetch;
reg        SC_execute;
reg        SC_dma;
reg        SC_interrupt;

reg        enabled;

reg [3:0]  horizontal_counter;
reg        horizontal_end;
  
reg [8:0]  vertical_counter;
reg        vertical_end;

reg        v_active;

reg        DMA_xfer;
reg [9:0]  addr_counter;


always @(posedge clk) begin
    case (SC)
      2'b00: SC_fetch     <= 1'b1;
      2'b01: SC_execute   <= 1'b1;
      2'b10: SC_dma       <= 1'b1;
      2'b11: SC_interrupt <= 1'b1;                  
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
        horizontal_counter <= 0;
      else
        horizontal_counter <= horizontal_counter+1;
    end

    horizontal_end <= horizontal_counter==bytes_per_line-1  ? 1'b1 : 1'b0;
    vertical_end   <= vertical_counter  ==lines_per_frame-1 ? 1'b1 : 1'b0;
end

always @(posedge clk) begin
    if(clk_enable && horizontal_end) begin
      if (vertical_end)
        vertical_counter <= 0;
      else
        vertical_counter <= vertical_counter + 1;
      
      EFx       <= ((vertical_counter >= 76  && vertical_counter < 80) || (vertical_counter >= 108 && vertical_counter < 112)) ? 1'b0 : 1'b1;
      //INT       <= (enabled && vertical_counter >= 78 && vertical_counter < 80)  ? 1'b0 : 1'b1;
      v_active  <= (enabled && vertical_counter >= 108 && vertical_counter < 112) ? 1'b1 : 1'b0;

      if((enabled && vertical_counter >= 78 && vertical_counter < 80)) begin
        INT <= 1'b0;
        $display("1_INT: %d vertical_counter %d enabled %d", INT, vertical_counter, enabled);
      end
      else begin
        INT <= 1'b1;
        $display("2_INT: %d vertical_counter %d enabled %d", INT, vertical_counter, enabled);        
      end
    end
end

assign DMAO     = (enabled && v_active && horizontal_counter >= 1 && horizontal_counter < 9) ? 1'b0 : 1'b1;
assign DMA_xfer = (enabled && SC_dma) ? 1'b1 : 1'b0;

always @(posedge clk) begin
    if(clk_enable) begin
      if (reset || (horizontal_end && vertical_end))
        addr_counter <= 1'd0;
      else if (DMA_xfer)
        addr_counter <= addr_counter + 1'd1;
    end 
end

assign mem_addr  = addr_counter;
assign mem_data  = data_in;
assign mem_wr_en = DMA_xfer;

endmodule
