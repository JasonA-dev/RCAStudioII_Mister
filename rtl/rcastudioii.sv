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
  input      [24:0] ioctl_addr,
	input       [7:0] ioctl_dout,

	input         pal,
	input         scandouble,

  input   [10:0] ps2_key,
//	output reg    ce_pix,

	output reg    HBlank,
	output reg    HSync,
	output reg    VBlank,
	output reg    VSync,
  output reg    video_de,
	output  [7:0] video
);


////////////////// VIDEO //////////////////////////////////////////////////////////////////

wire        Disp_On;
wire        Disp_Off;
wire        TPA = 1'b1;
wire        TPB = 1'b1;
reg  [1:0]  SC = 2'b01;
reg  [7:0]  DataIn;

wire   Clear;
wire   INT;
wire   DMAO;
wire   EFx;
wire   CompSync;
wire   Locked;

/*
cdp1861 cdp1861 (
    .clock(clk),
    .reset(reset),
    
    .Disp_On(1'b1),
    .Disp_Off(1'b0),
    .TPA(TPA),
    .TPB(TPB),
    .SC(SC),
    .DataIn(ram_q),

    .Clear(Clear),
    .INT(INT),
    .DMAO(DMAO),
    .EFx(EFx),

    .video(video),
    .CompSync(CompSync),
    .Locked(Locked),

    .VSync(VSync),
    .HSync(HSync),    
    .VBlank(VBlank),
    .HBlank(HBlank),
    .video_de(video_de)     
);
*/
pixie_dp pixie_dp (
    // front end, CDP1802 bus clock domain
    .clk(clk),
    .reset(reset),  
    .clk_enable(1'b1),

    .sc(SC),         
    .disp_on(1'b1),
    .disp_off(1'b0),
    .data(ram_q),     

    .dmao(DMAO),     
    .INT(INT),     
    .efx(EFx),

    // back end, video clock domain
    .video_clk(clk),
    .csync(CompSync),     
    .video(video),

    .VSync(VSync),
    .HSync(HSync),    
    .VBlank(VBlank),
    .HBlank(HBlank),
    .video_de(video_de)       
);

////////////////// KEYPAD //////////////////////////////////////////////////////////////////

wire       pressed = ps2_key[9];
wire [7:0] code    = ps2_key[7:0];
always @(posedge clk) begin
	reg old_state;
	old_state <= ps2_key[10];

	if(old_state != ps2_key[10]) begin
		case(code)
			'h16: btnKP1_1  <= pressed; // Keypad1 1
			'h1E: btnKP1_2  <= pressed; // Keypad1 2
      'h26: btnKP1_3  <= pressed; // Keypad1 3
      'h25: btnKP1_4  <= pressed; // Keypad1 4
      'h2E: btnKP1_5  <= pressed; // Keypad1 5
      'h36: btnKP1_6  <= pressed; // Keypad1 6
      'h3D: btnKP1_7  <= pressed; // Keypad1 7
      'h3E: btnKP1_8  <= pressed; // Keypad1 8
      'h46: btnKP1_9  <= pressed; // Keypad1 9
      'h45: btnKP1_0  <= pressed; // Keypad1 0
		endcase
	end

end

reg btnKP1_1 = 0;
reg btnKP1_2 = 0;
reg btnKP1_3 = 0;
reg btnKP1_4 = 0;
reg btnKP1_5 = 0;
reg btnKP1_6 = 0;
reg btnKP1_7 = 0;
reg btnKP1_8 = 0;
reg btnKP1_9 = 0;
reg btnKP1_0 = 0;

////////////////// CPU //////////////////////////////////////////////////////////////////

reg [7:0] cpu_din;
reg [7:0] cpu_dout;
wire cpu_inp;
wire cpu_out;

wire Q;
reg  [3:0] EF = 4'b0010;
// 1000  EF4 Key pressed on keypad 2
// 0100  EF3 Key pressed on keypad 1
// 0010  EF2 ?? Pixie
// 0001  EF1 ?? Video display monitoring

wire unsupported;

cdp1802 cdp1802 (
  .clock(clk),
  .resetq(~reset),

  .Q(Q),                // O external pin Q Turns the sound off and on. When logic '1', the beeper is on.
  .EF(EF),              // I 3:0 external flags EF1 to EF4

  .io_din(btnKP1_4),     
  .io_dout(),    
  .io_n(),              // O 2:0 IO control lines: N2,N1,N0
  .io_inp(),            // O IO input signal
  .io_out(),            // O IO output signal

  .unsupported(unsupported),

  .ram_rd(ram_rd),     
  .ram_wr(ram_wr),     
  .ram_a(ram_a),      
  .ram_q(ram_q),      
  .ram_d(ram_d)      
);

////////////////// RAM //////////////////////////////////////////////////////////////////

reg ram_cs;

wire          ram_rd; // RAM read enable
wire          ram_wr; // RAM write enable
wire  [15:0]  ram_a;  // RAM address
wire   [7:0]  ram_q;  // RAM read data
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
/*
rom #(.AW(11)) Rom_SingleCart
(
	.clock      (clk            ),
	.ce         (1'b1           ),
	.data_out   (romDo_SingleCart ),
	.a          (romA[10:0]     )
);
*/
dpram #(.ADDR(12)) dpram (

  .clk(clk),

	.a_ce(ram_rd),
	.a_wr(ram_wr),
	.a_din(ram_d),
	.a_dout(ram_q),
	.a_addr(ram_a),

	.b_ce(ioctl_download),
	.b_wr(ioctl_wr),
	.b_din(ioctl_dout),
	.b_dout(),
	.b_addr(ioctl_addr)
);

////////////////// DMA //////////////////////////////////////////////////////////////////

wire [7:0] rom_dout;
wire [7:0] cart_dout;
wire [7:0] pram_dout;
wire [7:0] vram_dout;
wire [7:0] mcart_dout;

wire dma_busy;

//0000-02FF	ROM 	      RCA System ROM : Interpreter
//0300-03FF	ROM	        RCA System ROM : Always present
//0400-07FF	ROM	        Games Programs, built in (no cartridge)
//0400-07FF	Cartridge	  Cartridge Games (when cartridge plugged in)
//0800-08FF	RAM	        System Memory, Program Memory etc.
//0900-09FF	RAM	        Display Memory
//0A00-0BFF	Cartridge	  (MultiCart) Available for Cartridge games if required, probably isn't.
//0C00-0DFF	RAM/ROM	    Duplicate of 800-9FF - the RAM is double mapped in the default set up. 
//                      This RAM can be disabled and ROM can be put here instead, 
//                      so assume this is ROM for emulation purposes.
//0E00-0FFF	Cartridge	  (MultiCart) Available for Cartridge games if required, probably isn't.

wire rom_cs   = AB ==? 16'b0000_xxxx_xxxx_xxxx;
wire cart_cs  = AB ==? 16'b0000_01xx_xxxx_xxxx; 
wire pram_cs  = AB ==? 16'b0000_1000_xxxx_xxxx; 
wire vram_cs  = AB ==? 16'b0000_1001_xxxx_xxxx; 
wire mcart_cs = AB ==? 16'b0000_101x_xxxx_xxxx; 

reg [7:0] DI;
wire [15:0] AB = ram_a;

always @(posedge clk) begin
  DI <= rom_cs ? rom_dout :
  cart_cs ? cart_dout :
  pram_cs ? pram_dout :
  vram_cs ? vram_dout :    
  mcart_cs ? mcart_dout : 8'hff;
end

dma dma(
  .clk(clk),
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

/////////////////////////////////////////////////////////////////////////////////////////

endmodule
