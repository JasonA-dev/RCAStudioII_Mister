`timescale 1ns/1ns
// top end ff for verilator

module top(

   input clk_48 /*verilator public_flat*/,
   //input clk_12 /*verilator public_flat*/,
   input reset/*verilator public_flat*/,
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
   output  reg  ioctl_wait=1'b0
   
);
   
   // Core inputs/outputs
   wire       pause;
   wire [7:0] audio;
   wire [8:0] rgb;
   wire [3:0] led/*verilator public_flat*/;
   reg [7:0]  trakball/*verilator public_flat*/;
   reg [7:0]  joystick/*verilator public_flat*/;
   reg [9:0]  playerinput/*verilator public_flat*/;  

   // Hardcode default switches
   reg [7:0]  sw1 = { 1'b0, 1'b0,2'b0,2'b0,2'b0 };
   reg [7:0]  sw2 = 8'h02;

   // Convert 3bpp output to 8bpp
   assign VGA_R = {rgb[2:0],rgb[2:0],rgb[2:1]};
   assign VGA_G = {rgb[5:3],rgb[5:3],rgb[5:4]};
   assign VGA_B = {rgb[8:6],rgb[8:6],rgb[8:7]};
    
   // MAP INPUTS FROM SIM
   // -------------------
   assign playerinput[9] = ~inputs[10]; // coin r
   assign playerinput[8] = ~inputs[9]; // coin m
   assign playerinput[7] = ~inputs[8]; // coin l
   assign playerinput[6] = 1'b1;       // self-test
   assign playerinput[5] = 1'b0;       // cocktail
   assign playerinput[4] = 1'b1;       // slam
   assign playerinput[3] = ~inputs[7]; // start 2
   assign playerinput[2] = ~inputs[6]; // start 1
   assign playerinput[1] = ~inputs[5]; // fire 2
   assign playerinput[0] = ~inputs[4]; // fire 1  
   assign joystick[7:4] = { ~inputs[0],~inputs[1],~inputs[2],~inputs[3] }; // right, left, down, up 1
   assign joystick[3:0] = { ~inputs[0],~inputs[1],~inputs[2],~inputs[3] }; // right, left, down, up 2
   assign pause = inputs[11];       // pause

   // MAP OUTPUTS
   assign AUDIO_L = {audio,audio};
   assign AUDIO_R = AUDIO_L;

   reg ce_pix;
   /*
   always @(posedge clk_48) begin
      reg old_clk;
      
      old_clk <= clk_12;
      ce_pix <= old_clk & ~clk_12;
   end
   */


rcastudioii rcastudio
(
	.clk(clk_48),
	.reset(reset),
	
	.pal(1'b1),
	.scandouble(forced_scandoubler),

	.ce_pix(ce_pix),

	.HBlank(HBlank),
	.HSync(HSync),
	.VBlank(VBlank),
	.VSync(VSync),

	.video(video)
);


endmodule
