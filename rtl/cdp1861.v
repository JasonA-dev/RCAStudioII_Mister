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

    input clock,
    input reset,

    input Disp_On,
    input Disp_Off,
    input TPA,
    input TPB,
    input [1:0] SC,
    input [7:0] DataIn,

    output              ram_rd,     // RAM read enable
    output              ram_wr,     // RAM write enable
    output     [15:0]   ram_a,      // RAM address
    input      [7:0]    ram_q,      // RAM read data
    output     [7:0]    ram_d,      // RAM write data

    output Clear,
    output reg INT,
    output reg DMAO,
    output reg EFx,

    output reg video,
    output reg CompSync,
    output Locked
);

//Line and Machine Cycle counter
reg lineCounter   = 'd263;
reg MCycleCounter = 'd28;
reg syncCounter   = 'd12;
    
reg DisplayOn;

reg VSync;
reg HSync;

reg [7:0] VideoShiftReg;

reg [7:0] cpu_din;
reg [7:0] cpu_dout;
wire cpu_inp;
wire cpu_out;

reg unsupported;

always @(posedge clock) begin

  if(~reset) begin
    lineCounter   <= 0;
    syncCounter   <= 0;
    MCycleCounter <= 0;
  end

  if (syncCounter != 0 || (MCycleCounter == 'd26 && lineCounter == 0 && TPA && (SC != 0))) begin
    syncCounter <= syncCounter + 1'd1;
  end

  if((TPB || TPA) && syncCounter == 0) begin
    MCycleCounter <= MCycleCounter + 1'd1;
  end

  if(MCycleCounter == 'd28) begin
    lineCounter <= lineCounter + 1'd1;
    MCycleCounter <= 0;
  end

  if (syncCounter == 'd12)
    syncCounter <= 0;

  if (lineCounter == 'd263)
    lineCounter <= 0;

  //Display On flag for controlling the DMA and Interrupt output
  if(Disp_On) 
    DisplayOn <= 1'b1;
  else if (Disp_Off || ~reset)
    DisplayOn <= 1'b0;

  //Flag Logic
  if ((lineCounter == 78 || lineCounter == 79) && DisplayOn)
    INT <= 1'b0;
  else
    INT <= 1'b1;

  if ((lineCounter >= 76 && lineCounter <= 79) || (lineCounter >= 205 && lineCounter <= 207))
    EFx <= 1'b0;
  else 
    EFx <= 1'b1;

end

always @(negedge clock) begin

  //Sync Timing
  CompSync <= ~(HSync ^ VSync);

  //VSync Logic
  if(lineCounter >= 'd16) 
    VSync <= 1'b1;
  else 
    VSync <= 1'b0;

  //HSync Logic
  if (MCycleCounter >= 3 | (MCycleCounter == 2 && TPA)) 
    HSync <= 1'b1;
  else
    HSync <= 1'b0;

  //DMA Logic
  if(lineCounter >= 'd80 && lineCounter <= 'd207 && ((MCycleCounter == 2 && TPA) || MCycleCounter >= 3 && MCycleCounter <= 19) && DisplayOn)
    DMAO <= 1'b0;
  else 
    DMAO <= 1'b1;

  //Video shift Register
  if(SC == 2 && TPB)
    VideoShiftReg <= DataIn;
  else if (~reset) 
    VideoShiftReg <= 0;
  else 
    VideoShiftReg <= VideoShiftReg << 1;

  video <= VideoShiftReg[7];

end


cdp1802 cdp1802 (
  .clock(clock),
  .resetq(reset),

  .Q(),          // O external pin Q
  .EF(),         // I 3:0 external flags EF1 to EF4

  .io_din(cpu_din),     
  .io_dout(cpu_dout),    
  .io_n(),       // O 2:0 IO control lines: N2,N1,N0
  .io_inp(cpu_inp),     // O IO input signal
  .io_out(cpu_out),     // O IO output signal

  .unsupported(unsupported),

  .ram_rd(ram_rd),     
  .ram_wr(ram_wr),     
  .ram_a(ram_a),      
  .ram_q(ram_q),      
  .ram_d(ram_d)      
);


endmodule