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

module cdp1861 (

    input               clock,
    input               reset,

    input               Disp_On,
    input               Disp_Off,
    input               TPA,
    input               TPB,
    input       [1:0]   SC,
    input       [7:0]   DataIn,

    output              Clear,
    output reg          INT,
    output reg          DMAO,
    output reg          EFx,

    output reg          video,
    output reg          CompSync,
    output              Locked,

    output reg  VSync,
    output reg  HSync,
    output wire  VBlank,
    output wire  HBlank,

    output reg  video_de     
);

//Line and Machine Cycle counter
reg [7:0] lineCounter;   // max 'd263;
reg [7:0] MCycleCounter; // max 'd28;
reg [7:0] syncCounter;   // max 'd12;
    
reg DisplayOn;

//assign VBlank = lineCounter > 79;
//assign HBlank = MCycleCounter > 28;
assign VBlank   = (lineCounter   < 64 && lineCounter   > 96);    
assign HBlank   = (MCycleCounter >= 'd3 && MCycleCounter <= 'd19);

reg [7:0] VideoShiftReg;

always @(posedge clock) begin

/*
  if(reset) begin
    lineCounter   <= 0;
    syncCounter   <= 0;
    MCycleCounter <= 0;
  end
*/
  if (syncCounter == 'd0 || (MCycleCounter == 'd26 && lineCounter == 'd0 && TPA && (SC != 2'b00))) begin
    syncCounter <= syncCounter + 1'd1;
  end

  if((TPB || TPA) && syncCounter <= 'd12) begin    
    MCycleCounter <= MCycleCounter + 1'd1;
  end

  if(MCycleCounter == 'd28) begin
    lineCounter <= lineCounter + 1'd1;
    MCycleCounter <= 'd0;
  end

  if (syncCounter == 'd12)
    syncCounter <= 'd0;

  if (lineCounter == 'd263) 
    lineCounter <= 'd0;

  //Display On flag for controlling the DMA and Interrupt output
  if(Disp_On) 
    DisplayOn <= 1'b1;
  else if (Disp_Off || ~reset)
    DisplayOn <= 1'b0;

  //Flag Logic
  if ((lineCounter == 'd78 || lineCounter == 'd79) && DisplayOn) 
    INT <= 1'b0;
  else 
    INT <= 1'b1;

  if ((lineCounter >= 'd76 && lineCounter <= 'd79) || (lineCounter >= 'd205 && lineCounter <= 'd207)) begin
    EFx <= 1'b0;
    video_de  <= 1'b0;   
  end
  else begin
    EFx <= 1'b1;
    video_de  <= 1'b1;      
  end

end

always @(negedge clock) begin

  //Sync Timing
  CompSync <= ~(HSync ^ VSync);

  //VSync Logic
  if(lineCounter == 'd0) 
    VSync <= 1'b1;
  else 
    VSync <= 1'b0;

  //HSync Logic
  if (MCycleCounter >= 'd3 | (MCycleCounter == 'd2 && TPA)) 
    HSync <= 1'b1;
  else
    HSync <= 1'b0;

  //DMA Logic
  if(lineCounter >= 'd80 && lineCounter <= 'd207 && ((MCycleCounter == 'd2 && TPA) || MCycleCounter >= 'd3 && MCycleCounter <= 'd19) && DisplayOn)
    DMAO <= 1'b0;
  else 
    DMAO <= 1'b1;

  //Video shift Register
  if(SC == 2'b01 && TPB)
    VideoShiftReg <= DataIn;
  else if (~reset) 
    VideoShiftReg <= 'd0;
  else 
    VideoShiftReg <= VideoShiftReg << 1;

  video <= VideoShiftReg[7];

end

endmodule