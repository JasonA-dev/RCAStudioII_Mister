//
// dpram.sv
//
// sdram controller implementation for the MiSTer board by
//
// Copyright (c) 2020 Frank Bruno
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

module dpram #(
    parameter data_width_g = 8,
    parameter addr_width_g = 14
) (
    input   wire                clk_sys,

    // Port A
    input   wire                ram_cs,    
    input   wire                ram_we,
    input   wire    [addr_width_g-1:0]  ram_ad,
    input   wire    [data_width_g-1:0]  ram_d,
    output  logic   [data_width_g-1:0]  ram_q,

    // Port B
    input   wire                ram_cs_b,    
    input   wire                ram_we_b,
 //   output  wire                b_ack,    
    input   wire    [addr_width_g-1:0]  ram_ad_b,
    input   wire    [data_width_g-1:0]  ram_d_b,
    output  logic   [data_width_g-1:0]  ram_q_b
);

// Shared memory
logic [data_width_g-1:0] mem [(2**addr_width_g)-1:0];

/*
initial begin
    mem = '{default:'0};
end
*/

// Port A
always @(posedge clk_sys) begin
    if(ram_cs) begin
        ram_q <= mem[ram_ad];
    end
    if(ram_we) begin
        mem[ram_ad] <= ram_d;
    end
end

// Port B
always @(posedge clk_sys) begin
  //  b_ack <= 1'b0;
    if(ram_cs_b) begin
        ram_q_b <= mem[ram_ad_b];
      //  b_ack <= 1'b1;        
      //  $display("b_dout %h b_dout %h b_addr %h", b_ack, b_dout, b_addr);           
    end
    if(ram_we_b) begin
        mem[ram_ad_b] <= ram_d_b;
    end
end

endmodule
