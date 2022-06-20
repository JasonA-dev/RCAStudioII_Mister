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

	//input         pal,
	//input         scandouble,

  input   [10:0] ps2_key,
	output reg    ce_pix,

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
reg  [1:0]  SC = 2'b01;
reg  [7:0]  video_din;

wire   INT;
wire   DMAO;
wire   EFx;
wire   Locked;

pixie_dp pixie_dp (
    // front end, CDP1802 bus clock domain
    .clk(clk),
    .reset(reset),  
    .clk_enable(1'b1),

    .sc(SC),         
    .disp_on(1'b1),
    .disp_off(1'b0),
    .data(video_din),     

    .dmao(DMAO),     
    .INT(INT),     
    .efx(EFx),

    // back end, video clock domain
    .video_clk(clk),
    .csync(ce_pix),     
    .video(video),

    .VSync(VSync),
    .HSync(HSync),    
    .VBlank(VBlank),
    .HBlank(HBlank),
    .video_de(video_de)       
);

////////////////// KEYPAD //////////////////////////////////////////////////////////////////

reg [7:0] btnKP1 = 8'hff;

wire       pressed = ps2_key[9];
wire [7:0] code    = ps2_key[7:0];
always @(posedge clk) begin
	reg old_state;
	old_state <= ps2_key[10];

	if(old_state != ps2_key[10]) begin
		case(code)
			'h16: btnKP1  <= 1'd1; // Keypad1 1
			'h1E: btnKP1  <= 1'd2; // Keypad1 2
      'h26: btnKP1  <= 1'd3; // Keypad1 3
      'h25: btnKP1  <= 1'd4; // Keypad1 4
      'h2E: btnKP1  <= 1'd5; // Keypad1 5
      'h36: btnKP1  <= 1'd6; // Keypad1 6
      'h3D: btnKP1  <= 1'd7; // Keypad1 7
      'h3E: btnKP1  <= 1'd8; // Keypad1 8
      'h46: btnKP1  <= 1'd9; // Keypad1 9
      'h45: btnKP1  <= 1'd0; // Keypad1 0
		endcase
	end

end

////////////////// CPU //////////////////////////////////////////////////////////////////

reg [7:0] cpu_din;
reg [7:0] cpu_dout;
wire cpu_inp;
wire cpu_out;

wire Q;
reg  [3:0] EF;
// 1000  EF4 Key pressed on keypad 2
// 0100  EF3 Key pressed on keypad 1
// 0010  EF2 
// 0001  EF1 Video display monitoring, driven by EFx from cpu

always @(posedge clk) begin
  if(EFx)
    EF = 4'b1101;
  else if (btnKP1 != 8'hff)
    EF = 4'b1011;
  else
    EF = 4'b1111;
end

wire unsupported;

cdp1802 cdp1802 (
  .clock    (clk),
  .resetq   (~reset),

  .Q        (Q),        // O external pin Q Turns the sound off and on. When logic '1', the beeper is on.
  .EF       (EF),       // I 3:0 external flags EF1 to EF4

  .io_din   (btnKP1),     
  .io_dout  (cpu_dout),    
  .io_n     (),         // O 2:0 IO control lines: N2,N1,N0
  .io_inp   (cpu_inp),         // O IO input signal
  .io_out   (cpu_out),         // O IO output signal

  .unsupported(unsupported),

  .ram_rd (ram_rd),     
  .ram_wr (ram_wr),     
  .ram_a  (ram_a),      
  .ram_q  (ram_q),      
  .ram_d  (ram_d)      
);

////////////////// RAM //////////////////////////////////////////////////////////////////

reg ram_cs;

wire          ram_rd; // RAM read enable
wire          ram_wr; // RAM write enable
wire  [15:0]  ram_a;  // RAM address
wire   [7:0]  ram_q;  // RAM read data
reg   [7:0]   ram_d;  // RAM write data

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
  .clk    (clk),

	.a_ce   (ram_rd),
	.a_wr   (ram_wr),
	.a_din  (ram_din),
	.a_dout (ram_q),
	.a_addr (ram_a),

	.b_ce   (ioctl_download),
	.b_wr   (ioctl_wr),
	.b_din  (ioctl_dout),
	.b_dout (),
	.b_addr (ioctl_addr)
);

////////////////// DMA //////////////////////////////////////////////////////////////////

wire [7:0] rom_dout;
wire [7:0] cart_dout;
wire [7:0] pram_dout;
wire [7:0] vram_dout;
wire [7:0] mcart_dout;

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

wire rom_cs   = ram_a ==? 16'b0000_xxxx_xxxx_xxxx;
wire cart_cs  = ram_a ==? 16'b0000_01xx_xxxx_xxxx; 
wire pram_cs  = ram_a ==? 16'b0000_1000_xxxx_xxxx; 
wire vram_cs  = ram_a ==? 16'b0000_1001_xxxx_xxxx; 
wire mcart_cs = ram_a ==? 16'b0000_101x_xxxx_xxxx; 

reg [7:0] ram_din;

// ram writes
always @(posedge clk) begin
  if (ram_wr) begin
    if(vram_cs) begin  
      if(ram_d < 2'd01) begin
        video_din <= 8'h50;
        ram_din <= 8'h50;
        //video_din <= ram_d;
        //$display("video_din %x addr %x", video_din, ram_a);
      end
    end
    else begin
      ram_din <= ram_d;  
      //$display("ram_din %x addr %x", ram_din, ram_a); 
    end
  end
end

// internal games still there if (0x402==2'hd1 && 0x403==2'h0e && 0x404==2'hd2 && 0x405==2'h39)
// 0x40e = game 1
// 0x439 = game 2
// 0x48b = game 3
// 0x48d = game 4
// 0x48f = game 5

/////////////////////////////////////////////////////////////////////////////////////////

endmodule
