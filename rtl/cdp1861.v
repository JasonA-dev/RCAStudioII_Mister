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
    input Reset_,

    input Disp_On,
    input Disp_Off,
    input TPA,
    input TPB,
    input [1:0] SC,
    input [7:0] DataIn,

    output Clear,
    output INT,
    output DMAO,
    output EFx,

    output Video,
    output CompSync_,
    output Locked
);

cdp1802 cdp1802 (
  .clock(clock),
  .resetq(),

  .Q(),          
  .EF(),         

  .io_din(),     
  .io_dout(),    
  .io_n(),       
  .io_inp(),     
  .io_out(),     

  .unsupported(),

  .ram_rd(),     
  .ram_wr(),     
  .ram_a(),      
  .ram_q(),      
  .ram_d()      
);

endmodule