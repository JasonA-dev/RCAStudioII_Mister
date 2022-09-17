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

module pixie_video_studioii
(
    // back end, video clock domain
    input               clk,
    input               reset, 

    output              csync,
    output              video,

    output  reg         VSync,
    output  reg         HSync,    
    output  reg         VBlank,
    output  reg         HBlank,
    output              video_de,      

    // front end, CDP1802 bus clock domain
    input              clk_enable,
    input        [1:0] SC,
    input              disp_on,
    input              disp_off,
    input        [7:0] data_in,

    output wire        DMAO,
    output reg         INT,
    output reg         EFx,

    output      [15:0] mem_addr
);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

parameter pixels_per_line         = 112; // (14 bytes x 8bits, constant for all 1861's)
parameter hsync_pixel             = 2;   // two cycles later to account for pipeline delay

parameter lines_per_frame         = 262; // (constant for all 1861's)
parameter vsync_line              = 2;  

parameter start_addr              = 16'h0900;
parameter end_addr                = start_addr + 8'hff;

parameter vertical_start_line     = 64;
parameter vertical_end_line       = 193;
parameter horizontal_start_pixel  = 16;
parameter horizontal_end_pixel    = 80;

//PAL
// interruptGraphicsMode_ = 74;
// startGraphicsMode_     = 76;
// endGraphicsMode_       = 267;
// endScreen_             = 312;
// videoHeight_           = 192;

//NTSC
// interruptGraphicsMode_ = 62;
// startGraphicsMode_     = 64;
// endGraphicsMode_       = 191;
// endScreen_             = 262;
// videoHeight_           = 128;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

reg         SC_fetch;
reg         SC_execute;
reg         SC_dma;
reg         SC_interrupt;

reg         display_enabled;
wire        DMA_xfer;

reg  [15:0] vram_addr;
reg   [7:0] frame_buffer[256];

reg   [7:0] pixel_shift_reg;
reg   [7:0] row_cache[8];
reg   [2:0] row_cache_counter = 0;
reg   [7:0] horizontal_pixel_counter;  
reg   [8:0] vertical_pixel_counter = 1;

////////////////////////// assignments  ////////////////////////////////////////////////////////////////////////////////

assign DMAO      = (display_enabled && VBlank==1'b0 && horizontal_pixel_counter >= 1 && horizontal_pixel_counter < 9) ? 1'b0 : 1'b1;
assign DMA_xfer  = (display_enabled && SC_dma) ? 1'b1 : 1'b0;

assign csync     = ~(HSync ^ VSync);
assign video_de  = ~(VBlank | HBlank);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

always @(posedge clk) begin
    case (SC)
      2'b00: SC_fetch     <= 1'b1;
      2'b01: SC_execute   <= 1'b1;
      2'b10: SC_dma       <= 1'b1;
      2'b11: SC_interrupt <= 1'b1;                  
    endcase

    if (clk_enable) begin
      if(reset)
        display_enabled <= 1'b0;
      else if (disp_on)
        display_enabled <= 1'b1;
      else if (disp_off)
        display_enabled <= 1'b0;
    end
end

assign mem_addr = vram_addr + start_addr;
always @(negedge clk) begin
	if(reset) begin
		vram_addr <= 8'h0;
	end
	else begin
		frame_buffer[vram_addr] <= data_in;    
		if (vram_addr == 8'hFF) begin
			vram_addr <= 8'h0;
		end               
		else vram_addr <= vram_addr + 1'b1;   
	end
end

// Video State Machine constants
localparam SM_VBLANK          = 0;
localparam SM_READ_ROW_CACHE  = 1;
localparam SM_LOAD_BYTE       = 2;
localparam SM_GENERATE_PIXELS = 3;
localparam SM_VIDEO_ROW       = 4;
reg  [7:0] video_state = SM_VBLANK;

localparam SMV_LEFT        = 0;
localparam SMV_START_PIXEL = 1;
localparam SMV_END_PIXEL   = 2;
localparam SMV_END_RIGHT   = 3;
localparam SMV_END_ROW     = 4;
reg [7:0] pixel_state = SMV_LEFT;

reg [15:0] video_byte_counter = 0;
reg  [2:0] byte_counter = 0;
reg  [7:0] tmp_byte_counter = 0;
reg  [7:0] tmp_row_cache_counter = 0;
reg  [7:0] tmp_horizontal_pixel_counter = 0;
reg  [7:0] tmp_vertical_pixel_counter = 0;

reg [7:0] nbit;
reg [3:0] line_repeat_counter = 4'd0;

always @(posedge clk) begin
    if(reset) begin
	    vertical_pixel_counter <= 1;
		 horizontal_pixel_counter <= 0;
	 end
	 else begin
		 case (video_state)
			SM_VBLANK: begin
			  if (vertical_pixel_counter == vertical_start_line) begin
				 video_state <= SM_VIDEO_ROW;
	//          $display("SM_VBLANK VBLANK: %d HBLANK: %d VPC %d HPC %d vertical_pixel_counter == vertical_start_line", VBlank, HBlank, vertical_pixel_counter, horizontal_pixel_counter);        
			  end
			  else if (vertical_pixel_counter == lines_per_frame) begin
				 vertical_pixel_counter <= 1;
				 line_repeat_counter <= 4'd0;
				 //$display("SM_VBLANK VBLANK: %d HBLANK: %d VPC %d HPC %d vertical_pixel_counter == lines_per_frame", VBlank, HBlank, vertical_pixel_counter, horizontal_pixel_counter);             
			  end        
			  if (horizontal_pixel_counter == pixels_per_line) begin
				 horizontal_pixel_counter <= 0;
				 vertical_pixel_counter <= vertical_pixel_counter + 1'd1;
				 //$display("SM_VBLANK VBLANK: %d HBLANK: %d VPC %d HPC %d horizontal_pixel_counter == pixels_per_line", VBlank, HBlank, vertical_pixel_counter, horizontal_pixel_counter);               
			  end
			  else begin 
				 horizontal_pixel_counter <= horizontal_pixel_counter + 1'd1;
			  end
			end
			SM_VIDEO_ROW: begin
			  //$display("SM_VIDEO_ROW load_byte byte_counter %d pixel_shift_reg %h row_cache[%d] %h vertical_pixel_counter %d horizontal_pixel_counter %d line_repeat_counter %d video_byte_counter %d",
			  //  byte_counter, pixel_shift_reg, byte_counter, row_cache[byte_counter], vertical_pixel_counter, horizontal_pixel_counter, line_repeat_counter, video_byte_counter);  
			  case (pixel_state)
				 SMV_LEFT: begin
					if(horizontal_pixel_counter == 1) begin
						if (line_repeat_counter == 4'd0) begin
						  line_repeat_counter <= 4'd4;
						  video_state <= SM_READ_ROW_CACHE;              
						  horizontal_pixel_counter <= horizontal_pixel_counter + 1'd1; 
						end
						
					end
					if(horizontal_pixel_counter == horizontal_start_pixel) begin
					  pixel_state <= SMV_START_PIXEL;
					end
					else begin
					  horizontal_pixel_counter <= horizontal_pixel_counter + 1'd1; 
					end
				 end
				 SMV_START_PIXEL: begin
					video_state <= SM_LOAD_BYTE;   
					pixel_state <= SMV_END_PIXEL;
					line_repeat_counter <= line_repeat_counter - 1'd1;              
				 end
				 SMV_END_PIXEL: begin
					if(horizontal_pixel_counter == horizontal_end_pixel) begin
					  pixel_state <= SMV_END_RIGHT;
					end
					else begin
					  horizontal_pixel_counter <= horizontal_pixel_counter + 1'd1; 
					end
				 end
				 SMV_END_RIGHT: begin
					if(horizontal_pixel_counter == pixels_per_line) begin
					  pixel_state <= SMV_END_ROW;
					end
					else
					  horizontal_pixel_counter <= horizontal_pixel_counter + 1'd1; 
				 end
				 SMV_END_ROW: begin
					if (vertical_pixel_counter == vertical_end_line) begin
					  video_byte_counter <= 0;              
					  video_state <= SM_VBLANK;
					end
					else begin
					  vertical_pixel_counter <= vertical_pixel_counter + 1'd1;            
					end
					horizontal_pixel_counter <= 0;
					pixel_state <= SMV_LEFT;    
				 end
			  endcase
			end

			SM_READ_ROW_CACHE: begin
			  row_cache[row_cache_counter] <= frame_buffer[row_cache_counter+video_byte_counter];
			  //$display("SM_READ_ROW_CACHE row_cache_counter %d video_byte_counter %d row_cache[%d] %h vertical_pixel_counter %d horizontal_pixel_counter %d HSync %d VSync %d HBlank %d VBlank %d", 
			  //            row_cache_counter, video_byte_counter, row_cache_counter, row_cache[row_cache_counter], vertical_pixel_counter, horizontal_pixel_counter, HSync, VSync, HBlank, VBlank);
			  if (row_cache_counter == 3'd7) begin
				 row_cache_counter <= 3'd0;
				 video_byte_counter <= video_byte_counter + 8'd8;    
	//          video_state <= SM_LOAD_BYTE;                 
				 video_state <= SM_VIDEO_ROW;                 
			  end  
			  else begin
				 row_cache_counter <= row_cache_counter + 1'd1;
			  end
			end
			SM_LOAD_BYTE: begin
				 pixel_shift_reg <= row_cache[byte_counter];
				 //$display("SM_LOAD_BYTE load_byte byte_counter %d pixel_shift_reg %h row_cache[%d] %h vertical_pixel_counter %d horizontal_pixel_counter %d line_repeat_counter %d",
				 //            byte_counter, pixel_shift_reg, byte_counter, row_cache[byte_counter], vertical_pixel_counter, horizontal_pixel_counter, line_repeat_counter); 
				 video_state <= SM_GENERATE_PIXELS;
			end
			SM_GENERATE_PIXELS: begin
			  if (nbit < 8'd7) begin
				 //$display("SM_GENERATE_PIXELS 1 load_byte byte_counter %d pixel_shift_reg %h row_cache[%d] %h vertical_pixel_counter %d horizontal_pixel_counter %d line_repeat_counter %d",
				 //            byte_counter, pixel_shift_reg, byte_counter, row_cache[byte_counter], vertical_pixel_counter, horizontal_pixel_counter, line_repeat_counter);           
				 pixel_shift_reg <= pixel_shift_reg << 1;  
				 horizontal_pixel_counter <= horizontal_pixel_counter + 1'd1;
				 nbit <= nbit + 1'd1;
			  end  
			  else begin
				 //$display("SM_GENERATE_PIXELS 2 load_byte byte_counter %d pixel_shift_reg %h row_cache[%d] %h vertical_pixel_counter %d horizontal_pixel_counter %d line_repeat_counter %d",
				 //            byte_counter, pixel_shift_reg, byte_counter, row_cache[byte_counter], vertical_pixel_counter, horizontal_pixel_counter, line_repeat_counter);            
				 nbit <= 8'd0;
				 horizontal_pixel_counter <= horizontal_pixel_counter + 1'd1;
				 if(byte_counter == 7) begin
					//$display("SM_GENERATE_PIXELS 3 load_byte byte_counter %d pixel_shift_reg %h row_cache[%d] %h vertical_pixel_counter %d horizontal_pixel_counter %d line_repeat_counter %d",
					//          byte_counter, pixel_shift_reg, byte_counter, row_cache[byte_counter], vertical_pixel_counter, horizontal_pixel_counter, line_repeat_counter);            
					pixel_shift_reg <= 0;                
					byte_counter <= 0;
					video_state <= SM_VIDEO_ROW;
				 end
				 else begin
					//$display("SM_GENERATE_PIXELS 4 load_byte byte_counter %d pixel_shift_reg %h row_cache[%d] %h vertical_pixel_counter %d horizontal_pixel_counter %d line_repeat_counter %d",
					//          byte_counter, pixel_shift_reg, byte_counter, row_cache[byte_counter], vertical_pixel_counter, horizontal_pixel_counter, line_repeat_counter);            
					byte_counter <= byte_counter + 1'd1; 
					video_state <= SM_LOAD_BYTE;
				 end
			  end  
			end
		 endcase 

		 EFx    <= ((vertical_pixel_counter >= (vertical_start_line - 8'd4) && vertical_pixel_counter <= vertical_start_line) || (vertical_pixel_counter >= (vertical_end_line - 8'd4) && vertical_pixel_counter <= vertical_end_line)) ? 1'b1 : 1'b0; 
		 INT    <= (vertical_pixel_counter >= (vertical_start_line - 8'd2) && vertical_pixel_counter <= vertical_start_line) ? 1'b1 : 1'b0;  

		 VSync <= (vertical_pixel_counter   > 252 && vertical_pixel_counter   <= 262) ? 1'b1 : 1'b0;  // VSYNC - 3 last lines for NTSC  

//		 HSync  <= (horizontal_pixel_counter < (horizontal_start_pixel) || horizontal_pixel_counter > (horizontal_end_pixel)) ? 1'b1 : 1'b0;
		 HSync  <= (horizontal_pixel_counter > 108 && horizontal_pixel_counter < 111) ? 1'b1 : 1'b0;
		 HBlank <= (horizontal_pixel_counter < horizontal_start_pixel || horizontal_pixel_counter > horizontal_end_pixel)  ? 1'b1 : 1'b0;  // 64 pixels wide
		 VBlank <= (vertical_pixel_counter   < vertical_start_line || vertical_pixel_counter   >= (vertical_end_line -1)) ? 1'b1 : 1'b0;  // 128 lines for NTSC  
	 end
end

assign video = pixel_shift_reg[7];

endmodule
