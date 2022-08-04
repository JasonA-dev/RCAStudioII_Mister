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
    parameter DATA = 8,
    parameter ADDR = 14
) (
    input   wire                clk,

    // Port A
    input   wire                a_ce,    
    input   wire                a_wr,
    output  wire                a_ack,      
    input   wire    [ADDR-1:0]  a_addr,
    input   wire    [DATA-1:0]  a_din,
    output  logic   [DATA-1:0]  a_dout,

    // Port B
    input   wire                b_ce,    
    input   wire                b_wr,
    output  wire                b_ack,    
    input   wire    [ADDR-1:0]  b_addr,
    input   wire    [DATA-1:0]  b_din,
    output  logic   [DATA-1:0]  b_dout
);

// Shared memory
logic [DATA-1:0] mem [(2**ADDR)-1:0];

/*
initial begin
    mem = '{default:'0};
end
*/

// Port A
always @(posedge clk) begin
    if(a_ce) begin
        a_dout <= mem[a_addr];
    end
    if(a_wr) begin
        mem[a_addr] <= a_din;
    end
end

// Port B
always @(posedge clk) begin
    b_ack <= 1'b0;
    if(b_ce) begin
        b_dout <= mem[b_addr];
        b_ack <= 1'b1;        
      //  $display("b_dout %h b_dout %h b_addr %h", b_ack, b_dout, b_addr);           
    end
    if(b_wr) begin
        mem[b_addr] <= b_din;
    end
end

endmodule
