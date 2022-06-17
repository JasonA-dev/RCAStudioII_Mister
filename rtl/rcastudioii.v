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
	
  input wire        ioctl_download,
  input wire  [7:0] ioctl_index,
  input wire        ioctl_wr,
  input  [24:0] ioctl_addr,
	input   [7:0] ioctl_dout,

	input         pal,
	input         scandouble,

	output reg    ce_pix,

	output reg    HBlank,
	output reg    HSync,
	output reg    VBlank,
	output reg    VSync,

	output  [7:0] video
);


wire        Disp_On;
wire        Disp_Off;
wire        TPA;
wire        TPB;
reg  [1:0]  SC;
reg  [7:0]  DataIn;

reg  [3:0]  EF;

wire  Clear;
reg   INT;
reg   DMAO;
reg   EFx;
reg   CompSync;
wire  Locked;

cdp1861 cdp1861 (
    .clock(clk),
    .reset(reset),
    
    .Disp_On(1'b1),
    .Disp_Off(1'b0),
    .TPA(TPA),
    .TPB(TPB),
    .SC(SC),
    .DataIn(DataIn),

    .Clear(Clear),
    .INT(INT),
    .DMAO(DMAO),
    .EFx(EFx),

    .video(video),
    .CompSync(CompSync),
    .Locked(Locked)
);

wire Q;
reg [7:0] cpu_din;
reg [7:0] cpu_dout;
wire cpu_inp;
wire cpu_out;

reg unsupported;

cdp1802 cdp1802 (
  .clock(clk),
  .resetq(reset),

  .Q(Q),                 // O external pin Q Turns the sound off and on. When logic '1', the beeper is on.
  .EF(EF),              // I 3:0 external flags EF1 to EF4

  .io_din(cpu_din),     
  .io_dout(cpu_dout),    
  .io_n(),              // O 2:0 IO control lines: N2,N1,N0
  .io_inp(cpu_inp),     // O IO input signal
  .io_out(cpu_out),     // O IO output signal

  .unsupported(unsupported),

  .ram_rd(ram_rd),     
  .ram_wr(ram_wr),     
  .ram_a(ram_a),      
  .ram_q(ram_q),      
  .ram_d(ram_d)      
);


wire          ram_rd; // RAM read enable
wire          ram_wr; // RAM write enable
wire  [15:0]  ram_a;  // RAM address
reg    [7:0]  ram_q;  // RAM read data
wire   [7:0]  ram_d;  // RAM write data

wire  [7:0]   romDo_StudioII;
wire  [7:0]   romDo_SingleCart;
wire [11:0]   romA;

rom #(.AW(11), .FN("../rom/studio2.hex")) Rom_StudioII
(
	.clock      (clk            ),
	.ce         (1'b1           ),
	.data_out   (romDo_StudioII ),
	.a          (romA[10:0]     )
);

rom #(.AW(11)) Rom_SingleCart
(
	.clock      (clk            ),
	.ce         (1'b1           ),
	.data_out   (romDo_SingleCart ),
	.a          (romA[10:0]     )
);

bram ram (
  .clk(clk),

  .bram_download(ioctl_download),
  .bram_wr(ioctl_wr),
  .bram_init_address(ioctl_addr),
  .bram_din(ioctl_dout),

  .cs(),
  .addr(),
  .dout()
);

/*
dma dma(
  .clk(clk_sys),
  .rdy(dma_rdy),
  .ctrl(dma_ctrl),
  .src_addr({ dma_src_hi, dma_src_lo }),
  .dst_addr({ dma_dst_hi, dma_dst_lo }),
  .addr(dma_addr), // => to AB
  .din(DI),
  .dout(dma_dout),
  .length(dma_length),
  .busy(dma_busy),
  .sel(dma_sel),
  .write(dma_write)
);
*/

always @(posedge clk) begin
  cpu_din <= ram_q;
end

endmodule
