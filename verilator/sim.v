`timescale 1ns/1ns
// top end ff for verilator

module top(

   input clk_48 /*verilator public_flat*/,
   input [11:0]  inputs/*verilator public_flat*/,

   output [7:0] VGA_R/*verilator public_flat*/,
   output [7:0] VGA_G/*verilator public_flat*/,
   output [7:0] VGA_B/*verilator public_flat*/,
   
   output VGA_HS,
   output VGA_VS,
   output VGA_HB,
   output VGA_VB,

   output [15:0] AUDIO_L,
   output [15:0] AUDIO_R,
   
   input        ioctl_download,
   input        ioctl_upload,
   input        ioctl_wr,
   input [24:0] ioctl_addr,
   input [7:0]  ioctl_dout,
   input [7:0]  ioctl_din,   
   input [7:0]  ioctl_index,
   output  reg  ioctl_wait=1'b0,

   input [10:0] ps2_key   
);
   
   // Core inputs/outputs
   wire [7:0] audio;
   wire [3:0] led/*verilator public_flat*/;

   wire VSync, HSync;
   wire VBlank, HBlank;

   assign VGA_VS = VSync;
   assign VGA_HS = HSync;
   assign VGA_VB = VBlank;
   assign VGA_HB = HBlank;

   // Convert 1bpp output to 8bpp
   assign VGA_R = {8{video}};
   assign VGA_G = {8{video}};
   assign VGA_B = {8{video}};
    
   // MAP OUTPUTS
   assign AUDIO_L = {audio,audio};
   assign AUDIO_R = AUDIO_L;

wire ce_pix = 1'b1;
wire reset = ioctl_download;

reg key_strobe;
wire key_strobe = old_keystb ^ ps2_key[10];
reg old_keystb = 0;
always @(posedge clk_48) old_keystb <= ps2_key[10];

rcastudioii rcastudio
(
	.clk(clk_48),
	.reset(reset),
	
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),

	.ps2_key(ps2_key),
	//.ce_pix(ce_pix),

	.HBlank(HBlank),
	.HSync(HSync),
	.VBlank(VBlank),
	.VSync(VSync),

	.video(video)
);

endmodule
