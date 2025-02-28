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
	input              clk_sys,
	input              clk_1m76,
	input              clk_vid,
	input              reset,
	
	input wire         ioctl_download,
	input wire   [7:0] ioctl_index,
	input wire         ioctl_wr,
	input       [24:0] ioctl_addr,
	input        [7:0] ioctl_dout,

	input       [10:0] ps2_key,
	input  reg         ce_pix,

	output reg         HBlank,
	output reg         HSync,
	output reg         VBlank,
	output reg         VSync,
	output reg         video_de,
	output             video
);

////////////////// VIDEO //////////////////////////////////////////////////////////////////

wire        Disp_On;
wire        Disp_Off;
reg  [1:0]  SC = 2'b10;
reg  [7:0]  video_din;

wire        INT;
wire        DMAO;
wire        EFx;
wire        Locked;

reg         vram_rd;

pixie_video pixie_video (
    // front end, CDP1802 bus clock domain
    .clk        (clk_sys),    // I
    .reset      (reset),      // I
    .clk_enable (ce_pix),     // I      

    .SC         (SC),         // I [1:0]
    //Temp hard coded display always on.
//    .disp_on    (io_n[0]),    // I
//    .disp_off   (~io_n[0]),   // I 
    .disp_on    (1'b1),    // I
    .disp_off   (1'b0),   // I 

    .data_addr  (vram_addr),  // O [9:0]
    .data_in    (video_din),  // I [7:0]    

    .DMAO       (DMAO),       // O
    .INT        (INT),        // O
    .EFx        (EFx),        // O

    // back end, video clock domain
    .video_clk  (clk_sys),    // I
    .csync      (),           // O
    .video      (video),      // O

    .VSync      (VSync),      // O
    .HSync      (HSync),      // O
    .VBlank     (VBlank),     // O
    .HBlank     (HBlank),     // O
    .video_de   (video_de)    // O    
);

////////////////// KEYPAD //////////////////////////////////////////////////////////////////

//The CPU will send out the key it wants to scan for over IO Port 1, so we latch on cpu_dout[3:0] once io_n[1] and io_out goes high.
reg  [3:0] keylatch = 4'h0;
always @(posedge clk_sys) if(io_n[1] && io_out) keylatch = cpu_dout[3:0];

wire       pressed = ps2_key[9];
wire [7:0] code    = ps2_key[7:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];

	if(old_state != ps2_key[10]) begin
		case(code)
			'h45: playerA[0]  <= pressed; // 12'b000000000001; // Keypad1 0
			'h16: playerA[1]  <= pressed; // 12'b000000000010; // Keypad1 1
			'h1E: playerA[2]  <= pressed; // 12'b000000000100; // Keypad1 2
			'h26: playerA[3]  <= pressed; // 12'b000000001000; // Keypad1 3
			'h25: playerA[4]  <= pressed; // 12'b000000010000; // Keypad1 4
			'h2E: playerA[5]  <= pressed; // 12'b000000100000; // Keypad1 5
			'h36: playerA[6]  <= pressed; // 12'b000001000000; // Keypad1 6
			'h3D: playerA[7]  <= pressed; // 12'b000010000000; // Keypad1 7
			'h3E: playerA[8]  <= pressed; // 12'b000100000000; // Keypad1 8
			'h46: playerA[9]  <= pressed; // 12'b001000000000; // Keypad1 9

			'h4D: playerB[0]  <= pressed; // 12'b000000000001; // Keypad2 P 
			'h15: playerB[1]  <= pressed; // 12'b000000000010; // Keypad2 Q
			'h1D: playerB[2]  <= pressed; // 12'b000000000100; // Keypad2 W
			'h24: playerB[3]  <= pressed; // 12'b000000001000; // Keypad2 E
			'h2D: playerB[4]  <= pressed; // 12'b000000010000; // Keypad2 R
			'h2C: playerB[5]  <= pressed; // 12'b000000100000; // Keypad2 T
			'h35: playerB[6]  <= pressed; // 12'b000001000000; // Keypad2 Y
			'h3C: playerB[7]  <= pressed; // 12'b000010000000; // Keypad2 U
			'h43: playerB[8]  <= pressed; // 12'b000100000000; // Keypad2 I
			'h44: playerB[9]  <= pressed; // 12'b001000000000; // Keypad2 O
		endcase
	end
end
reg  [9:0] playerA = 10'h0;
reg  [9:0] playerB = 10'h0;

////////////////// CPU //////////////////////////////////////////////////////////////////

wire  [3:0] EF; // = 4'b1111;
assign EF = {playerB[keylatch], playerA[keylatch],1'b1,EFx};

reg  [7:0] cpu_din;
reg  [7:0] cpu_dout;
wire       Q;
wire       unsupported;
wire [2:0] io_n;
wire       io_inp;
wire       io_out;

reg [15:0] cpu_ram_addr;
reg  [7:0] cpu_ram_din;
reg  [7:0] cpu_ram_dout;

reg WAIT_N      = 1'b0;
reg dma_in_req  = 1'b0;
//reg dma_out_req = 1'b0;

//wire TPA;
//wire TPB;
wire MWR_N;
wire MRD_N;
cdp1802 cdp1802 (
  .CLOCK        (clk_sys),
  .CLEAR_N      (~reset),

  .Q            (Q),            // O external pin Q Turns the sound off and on. When logic '1', the beeper is on.
  .EF           (EF),           // I 3:0 external flags EF1 to EF4

  .WAIT_N       (WAIT_N),       // I
  .INT_N        (~INT),         // I
  .dma_in_req   (dma_in_req),   // I
  .dma_out_req  (DMAO),         // I  TODO: check
  .SC           (SC),           // O

  .io_din       (cpu_din),      // I
  .io_dout      (cpu_dout),     // O
  .io_n         (io_n),         // O 2:0 IO control lines: N2,N1,N0  (N0 used for display on/off)
  .io_inp       (io_inp),       // O IO input signal
  .io_out       (io_out),       // O IO output signal

  .unsupported  (unsupported),  // O

  .ram_rd       (ram_rd),       // O MRD_N
  .ram_wr       (ram_wr),       // O MWR_N
  .ram_a        (ram_a),        // O cpu_ram_addr
  .ram_q        (ram_q),        // I DI
  .ram_d        (ram_d)        // O cpu_ram_dout

  //.TPA          (TPA),          // O Timing Pulse  (RAM)
  //.TPB          (TPB)           // O Timing Pulse  (IO)
);
/*
cosmac cosmac (
   .clk         (clk_sys),     // I
   .clk_enable  (1'b1),        // I
   .clear       (~reset),      // I
   .dma_in_req  (dma_in_req),  // I
   .dma_out_req (dma_out_req), // I
   .int_req     (INT_N),       // I
   .wait_req    (wait_req),    // I
   .ef          (EF),          // I [4:1]
   .data_in     (ram_q),       // I [7:0]
   .data_out    (ram_d),       // O [7:0]
   .address     (ram_a),       // O [15:0]
   .mem_read    (ram_rd),      // O
   .mem_write   (ram_wr),      // O
   .io_port     (io_n),        // O [2:0]
   .q_out       (Q),           // O
   .sc          (SC)           // O [1:0]
);
*/

////////////////// RAM //////////////////////////////////////////////////////////////////

reg          ram_cs;
reg          ram_rd; // RAM read enable
reg          ram_wr; // RAM write enable
reg   [7:0]  ram_d;  // RAM write data
reg  [15:0]  ram_a;  // RAM address
reg   [7:0]  ram_q;  // RAM read data

/*
wire  [7:0]  romDo_StudioII;
wire [11:0]  romA;

rom #(.AW(11), .FN("../rom/studio2.hex")) Rom_StudioII
(
	.clock      (clk_sys        ),
	.ce         (1'b1           ),
	.data_out   (romDo_StudioII ),
	.a          (romA[10:0]     )
);
*/////////

reg cpu_wr;
//reg clk_mem;
//assign clk_mem = ioctl_download ? clk_vid : clk_sys;
assign cpu_wr = (ram_a[11:0] >= 12'h800 && ram_a[11:0] < 12'hA00) ? ram_wr : 1'b0;
dpram #(8, 12) dpram
(
	.clock(clk_sys),
	.address_a(ioctl_download ? ioctl_addr[11:0] + (ioctl_index > 0 ? 12'h0400 : 12'h0 ) : ram_a[11:0]),
	.wren_a(ioctl_wr | cpu_wr),
	.data_a(ioctl_download ? ioctl_dout : ram_d),
	.q_a(ram_q),

	.wren_b(1'b0),
	.address_b(vram_addr[11:0]),
	.data_b(),
	.q_b(video_din)
);

////////////////// DMA //////////////////////////////////////////////////////////////////

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

/*
wire rom_cs   = ram_a ==? 16'b0000_00xx_xxxx_xxxx;
wire cart_cs  = ram_a ==? 16'b0000_01xx_xxxx_xxxx; 
wire pram_cs  = ram_a ==? 16'b0000_1000_xxxx_xxxx; 
wire vram_cs  = ram_a ==? 16'b0000_1001_xxxx_xxxx; 
wire mcart_cs = ram_a ==? 16'b0000_101x_xxxx_xxxx; 
*/

reg  [15:0] vram_addr;
//wire [15:0] AB = dma_busy ? dma_addr : ram_a;
//wire  [7:0] DO = dma_busy ? dma_dout : ram_d;
//wire pram_we = pram_cs ? dma_busy ? ~dma_write : ~ram_wr : 1'b1;
//wire vram_we = vram_cs ? dma_busy ? ~dma_write : ~ram_wr : 1'b1;

/*
always @(negedge clk_sys) begin
  DI <= rom_cs   ? ram_d :
        cart_cs  ? ram_d :
        pram_cs  ? ram_d :
        vram_cs  ? ram_d :        
        mcart_cs ? ram_d : 
        8'hff;     
end
*/

//reg        portb_ce;
//reg        portb_wr;
//reg  [7:0] portb_din;
//reg  [7:0] portb_dout;
//reg [15:0] portb_addr;
//always @(posedge clk_sys) begin
//  portb_ce  <= 1'b0;
//  portb_wr  <= 1'b0;
//  if(ioctl_download) begin
//    portb_ce   <= ioctl_download;
//    portb_wr   <= ioctl_wr;
//    portb_din  <= ioctl_dout;
//    portb_addr <= ioctl_index==0 ? ioctl_addr[15:0] : (16'h0400 + ioctl_addr[15:0]);
//  end
//  else if(vram_addr >= 'h0900) begin
//    portb_ce   <= 1'b1;
//    portb_addr <= vram_addr;
//    video_din  <= portb_dout;        
//  end
//end

// internal games still there if (0x402==2'hd1 && 0x403==2'h0e && 0x404==2'hd2 && 0x405==2'h39)
// 0x40e = game 1
// 0x439 = game 2
// 0x48b = game 3
// 0x48d = game 4
// 0x48f = game 5
/*
wire        dma_rdy = DMAO;
reg         dma_ctrl = 1'b1;
reg  [15:0] dma_addr;
reg   [7:0] DI;
wire  [7:0] dma_dout;
reg   [7:0] dma_length = 8'b1;

dma dma (
  .clk      (clk_sys),      // I
  .rdy      (dma_rdy),      // I
  .ctrl     (dma_ctrl),     // I
  .src_addr (ram_a),        // I 15:0
  .dst_addr (ram_a),        // I 15:0
  .addr     (dma_addr),     // O 15:0 => to AB
  .din      (DI),           // I 7:0
  .dout     (dma_dout),     // I 7:0
  .length   (dma_length),   // I
  .busy     (dma_busy),     // O
  .sel      (dma_sel),      // O
  .write    (dma_write)     // O
);
*/
/////////////////////////////////////////////////////////////////////////////////////////

endmodule
